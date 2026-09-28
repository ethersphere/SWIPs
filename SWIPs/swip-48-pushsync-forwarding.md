---
swip: SWIP 48
title: Pushsync forwarding from in-AOR full nodes
author: lat-murmeldjur
status: Draft
type: Standards Track
category: Core
created: 2026-05-25
discussions-to: https://github.com/ethersphere/bee/issues/5400
requires: https://github.com/ethersphere/bee/pull/5390
---

# SWIP 048 - Pushsync forwarding from in-AOR full nodes

## Summary

Pushsync should keep a chunk moving toward the closest currently selectable reachable peer. A full node that is inside the chunk's area of responsibility will store the chunk locally, but a local receipt should be a time bounded fallback, not the first result returned upstream.

This SWIP builds on `bee#5390`, which addresses out-of-depth storing, shallow receipts, and false `ChunkSynced` reporting. The additional change is limited to forwarder behaviour: an in-AOR full node should not stop the push path while normal forwarding can still progress, and `ErrWantSelf` should not bypass the overdraft refresh path when temporary accounting skips may soon clear.

## Problem statement

A Pushsync receipt shows that a chunk reached a node that considers itself responsible for storing it. The first in-AOR full node on a route is a valid local storer, but it is not necessarily the closest currently selectable reachable candidate visible through topology and accounting.

If that node stores the chunk, signs a receipt, and stops forwarding immediately, a better candidate may receive the chunk only later through pullsync. This makes the push path harder to reason about and may make successful delivery depend on timing outside the push itself.

There is a related overdraft case. Forwarder peer selection includes the current node. If peers are temporarily skipped because of accounting overdraft, peer selection may return `ErrWantSelf` instead of `ErrNotFound`. Treating this as final can skip the refresh wait and jump too early to local receipt creation or failure.

The intended rule is simple: full in-AOR nodes store locally, forwarding should continue when possible, and local receipts should be lazy fallbacks for currently reachable full in-AOR nodes only.

## Proposal

When a full node receives a chunk and is inside the chunk's AOR, it should validate the stamp and write the chunk to reserve. Reachability should not be required for this local reserve write.

Reachability matters for local receipt fallback. A reachable full in-AOR node may sign and return a local receipt if the forwarding path reaches a fallback condition. A full in-AOR node that is not reachable may still store the chunk, but should not become a terminal receipt issuer. It should forward or pass back a downstream receipt; if no forwarding path succeeds, it should return an error upstream.

The node should not sign its own receipt before fallback is actually used. In the common case, a downstream receipt arrives first and local signing is unnecessary. Fallback eligibility must be checked again at signing time, using current reachability and storage radius.

A fallback condition is one of the following:

- the fallback timeout expires;
- normal peer selection reaches terminal no-path state with no refreshable overdraft skip and no in-flight downstream send;
- the forwarding attempts fail under the existing retry budget and no in-flight downstream send can still return a receipt.

`ErrWarmup`, handler context cancellation, and handler deadline expiry are not fallback conditions and must not be converted into local receipts.

A fallback timeout of `10s` is suggested. The timer should be tied to full-node in-AOR storage eligibility, not to reachability at the moment forwarding starts. This allows a node that becomes reachable during the fallback window to sign only if it is currently eligible at signing time. If a downstream send starts after an overdraft wait, the fallback timeout should restart for that send.

Forwarder peer selection should keep its existing behaviour, including self, so that `ErrWantSelf` remains a meaningful decision point. If `ErrWantSelf` is returned while overdraft-skipped peers may become pushable, the forwarder should wait for the refresh interval and retry using the same skip-list pruning behaviour already used for `ErrNotFound`. It should keep doing this until forwarding progresses, another terminal result is reached, or the fallback timeout expires.

If a local fallback receipt is returned while a downstream send is already in flight, the in-flight send may still complete under the existing bounded Pushsync send timeout and apply its accounting action. Its later result does not need to be propagated upstream.

Nodes outside the AOR, and nodes that are not full nodes, must not store the chunk for this fallback path and must not issue local receipts.

This proposal does not weaken strict receipt validation from `bee#5390`. Origins should continue to reject shallow receipts. Forwarders may keep the existing pass-through behaviour; correctness is preserved because the origin validates the final receipt.

## Rationale

Returning a local receipt immediately is simple, but it stops the push path before the closest selectable reachable candidate has had a fair chance to receive the chunk. Returning a local receipt first and forwarding only in the background also favours a lower-proximity result even when a better downstream receipt may arrive shortly after.

The proposed behaviour separates local storage from local receipt creation. Storage protects the chunk as soon as an in-AOR full node sees it. Receipt creation remains lazy and bounded, so the normal forwarding path still gets a fair chance to produce the preferred receipt.

## One possible implementation plan on top of `bee#5390`

The swip implementation can be split into two parts.

### Part 1 - Forwarding fallback and overdraft-aware `ErrWantSelf`

This change keeps the existing `pushToClosest(ctx, ch, origin)`, `closestPeer(...)`, and `checkReceipt(...)` signatures. It is limited to the handler's local-store path and a fallback timer inside the existing `pushToClosest` loop.

Part 1 intends to produce the following behaviour:

- full in-AOR nodes write the chunk to reserve, even if they are not reachable;
- local fallback signing is allowed only when the node is currently full, reachable, and inside the current storage radius;
- local signing is lazy and uses the current storage radius at signing time;
- fallback signing is triggered only by a fallback condition, not by warmup or context cancellation;
- normal forwarder selection is kept, including self;
- `ErrNotFound` and forwarder `ErrWantSelf` use the same `skip.PruneExpiresAfter(...)` overdraft-refresh logic;
- the fallback timer is enabled by full-node in-AOR storage eligibility, while reachability is checked only at signing time;
- the fallback timeout restarts when refresh succeeds and a downstream send starts;
- already-started downstream sends may complete and apply accounting under their existing bounded send context;
- handler-delivered CAC chunks are not unwrapped twice.

Suggested patch:

```diff
diff --git a/pkg/pushsync/pushsync.go b/pkg/pushsync/pushsync.go
--- a/pkg/pushsync/pushsync.go
+++ b/pkg/pushsync/pushsync.go
@@ -47,6 +47,7 @@
 const (
 	defaultTTL         = 30 * time.Second // request time to live
 	preemptiveInterval = 5 * time.Second  // P90 request time to live
+	storerFallbackTTL  = 10 * time.Second // in-AOR self receipt fallback
 	skiplistDur        = 5 * time.Minute
 	overDraftRefresh   = time.Millisecond * 600
 )
@@ -253,7 +254,9 @@
 		return fmt.Errorf("pushsync: storage radius: %w", err)
 	}
 
-	store := func(ctx context.Context) error {
+	var storedChunk swarm.Chunk
+
+	putLocal := func(ctx context.Context) error {
 		ps.metrics.Storer.Inc()
 
 		chunkToPut, err := ps.validStamp(chunk)
@@ -261,50 +264,42 @@
 			return fmt.Errorf("invalid stamp: %w", err)
 		}
 
-		err = ps.store.ReservePutter().Put(ctx, chunkToPut)
-		if err != nil {
+		if err := ps.store.ReservePutter().Put(ctx, chunkToPut); err != nil {
 			return fmt.Errorf("reserve put: %w", err)
 		}
 
-		signature, err := ps.signer.Sign(chunkToPut.Address().Bytes())
-		if err != nil {
-			return fmt.Errorf("receipt signature: %w", err)
-		}
+		storedChunk = chunkToPut
+		return nil
+	}
 
-		// return back receipt
-		debit, err := ps.accounting.PrepareDebit(ctx, p.Address, price)
+	signLocalReceipt := func() (*pb.Receipt, bool, error) {
+		currentRadius, err := ps.radius()
 		if err != nil {
-			return fmt.Errorf("prepare debit to peer %s before writeback: %w", p.Address.String(), err)
+			return nil, false, fmt.Errorf("storage radius: %w", err)
 		}
-		defer debit.Cleanup()
 
-		attemptedWrite = true
+		currentPO := swarm.Proximity(ps.address.Bytes(), storedChunk.Address().Bytes())
+		if !ps.fullNode || !ps.topologyDriver.IsReachable() || currentPO < currentRadius {
+			return nil, false, nil
+		}
 
-		receipt := pb.Receipt{Address: chunkToPut.Address().Bytes(), Signature: signature, Nonce: ps.nonce, StorageRadius: uint32(rad)}
-		if err := w.WriteMsgWithContext(ctx, &receipt); err != nil {
-			return fmt.Errorf("send receipt to peer %s: %w", p.Address.String(), err)
+		signature, err := ps.signer.Sign(storedChunk.Address().Bytes())
+		if err != nil {
+			return nil, false, fmt.Errorf("receipt signature: %w", err)
 		}
 
-		return debit.Apply()
+		return &pb.Receipt{
+			Address:       storedChunk.Address().Bytes(),
+			Signature:     signature,
+			Nonce:         ps.nonce,
+			StorageRadius: uint32(currentRadius),
+		}, true, nil
 	}
 
-	if ps.topologyDriver.IsReachable() && swarm.Proximity(ps.address.Bytes(), chunkAddress.Bytes()) >= rad {
-		stored, reason = true, "is within AOR"
-		return store(ctx)
-	}
-
-	switch receipt, err := ps.pushToClosest(ctx, chunk, false); {
-	case errors.Is(err, topology.ErrWantSelf):
-		// Out-of-AOR chunks are unreachable via retrieval even when not
-		// evicted; let the origin try the next peer instead.
-		if swarm.Proximity(ps.address.Bytes(), chunkAddress.Bytes()) < rad {
-			ps.metrics.OutOfDepthStoring.Inc()
-			return ErrOutOfDepthStoring
+	writeReceipt := func(ctx context.Context, receipt *pb.Receipt) error {
+		if receipt == nil {
+			return ErrNoPush
 		}
-		stored, reason = true, "want self"
-		return store(ctx)
-	case err == nil:
-		ps.metrics.Forwarder.Inc()
 
 		debit, err := ps.accounting.PrepareDebit(ctx, p.Address, price)
 		if err != nil {
@@ -314,17 +309,57 @@
 
 		attemptedWrite = true
 
-		// pass back the receipt
 		if err := w.WriteMsgWithContext(ctx, receipt); err != nil {
 			return fmt.Errorf("send receipt to peer %s: %w", p.Address.String(), err)
 		}
 
 		return debit.Apply()
+	}
+
+	selfPO := swarm.Proximity(ps.address.Bytes(), chunkAddress.Bytes())
+	canLocalStore := ps.fullNode && selfPO >= rad
+
+	if canLocalStore {
+		stored, reason = true, "is within AOR"
+		if err := putLocal(ctx); err != nil {
+			return err
+		}
+
+		receipt, err := ps.pushToClosest(ctx, storedChunk, false)
+		if err != nil {
+			if ctxErr := ctx.Err(); ctxErr != nil {
+				return ctxErr
+			}
+			if errors.Is(err, ErrWarmup) || errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
+				return err
+			}
+
+			localReceipt, ok, signErr := signLocalReceipt()
+			if signErr != nil {
+				return signErr
+			}
+			if !ok {
+				return err
+			}
+			receipt = localReceipt
+		}
+
+		return writeReceipt(ctx, receipt)
+	}
+
+	switch receipt, err := ps.pushToClosest(ctx, chunk, false); {
+	case errors.Is(err, topology.ErrWantSelf):
+		ps.metrics.OutOfDepthStoring.Inc()
+		return ErrOutOfDepthStoring
+	case err == nil:
+		ps.metrics.Forwarder.Inc()
+		return writeReceipt(ctx, receipt)
 	default:
 		ps.metrics.Forwarder.Inc()
 		return fmt.Errorf("handler: push to closest chunk %s: %w", chunkAddress, err)
 
 	}
+
 }
 
 // PushChunkToClosest sends chunk to the closest peer by opening a stream. It then waits for
@@ -402,6 +437,46 @@
 		return nil, fmt.Errorf("pushsync: storage radius: %w", err)
 	}
 
+	storerFallback := !origin && ps.fullNode && swarm.Proximity(ps.address.Bytes(), ch.Address().Bytes()) >= rad
+	var fallbackTimer *time.Timer
+	var fallbackC <-chan time.Time
+	if storerFallback {
+		fallbackTimer = time.NewTimer(storerFallbackTTL)
+		defer fallbackTimer.Stop()
+		fallbackC = fallbackTimer.C
+	}
+
+	resetFallback := func() {
+		if fallbackTimer == nil {
+			return
+		}
+		if !fallbackTimer.Stop() {
+			select {
+			case <-fallbackTimer.C:
+			default:
+			}
+		}
+		fallbackTimer.Reset(storerFallbackTTL)
+	}
+
+	waitOverdraftRefresh := func() error {
+		ps.metrics.OverdraftRefresh.Inc()
+		if ps.overDraftRefreshLimiter.Allow() {
+			ps.logger.Debug("sleeping to refresh overdraft balance")
+		}
+
+		t := time.NewTimer(overDraftRefresh)
+		defer t.Stop()
+		select {
+		case <-t.C:
+			return nil
+		case <-fallbackC:
+			return topology.ErrWantSelf
+		case <-ctx.Done():
+			return ctx.Err()
+		}
+	}
+
 	skip := skippeers.NewList(0)
 	defer skip.Close()
 
@@ -409,6 +484,8 @@
 		select {
 		case <-ctx.Done():
 			return nil, ErrNoPush
+		case <-fallbackC:
+			return nil, topology.ErrWantSelf
 		case <-preemptiveTicker:
 			retry()
 		case <-retryC:
@@ -424,25 +501,18 @@
 			// overdraft-skipped; wait for refresh before falling back to self.
 			if errors.Is(err, topology.ErrNotFound) || errors.Is(err, topology.ErrWantSelf) {
 				if skip.PruneExpiresAfter(idAddress, overDraftRefresh) > 0 {
-					ps.metrics.OverdraftRefresh.Inc()
-					if ps.overDraftRefreshLimiter.Allow() {
-						ps.logger.Debug("sleeping to refresh overdraft balance")
-					}
-
-					select {
-					case <-time.After(overDraftRefresh):
-						retry()
-						continue
-					case <-ctx.Done():
-						return nil, ctx.Err()
+					if err := waitOverdraftRefresh(); err != nil {
+						return nil, err
 					}
+					retry()
+					continue
 				}
 			}
 
 			if errors.Is(err, topology.ErrNotFound) {
 				if inflight == 0 {
 					if ps.fullNode {
-						if cac.Valid(ch) {
+						if origin && cac.Valid(ch) {
 							go ps.unwrap(ch)
 						}
 						// prefer a shallow peer over self-store when one exists
@@ -488,6 +558,7 @@
 
 			ps.metrics.TotalSendAttempts.Inc()
 			inflight++
+			resetFallback()
 
 			go ps.push(ctx, resultChan, peer, ch, action)
 
@@ -531,6 +602,9 @@
 	if shallowReceiptResult != nil {
 		return shallowReceiptResult, ErrShallowReceipt
 	}
+	if storerFallback {
+		return nil, topology.ErrWantSelf
+	}
 	return nil, ErrNoPush
 }
```

Possible tests for Part 1:

```text
TestInAORFullNodeStoresEvenWhenNotReachable
TestUnreachableInAORFullNodeDoesNotSignFallback
TestLightNodeNeverStoresOrSignsFallback
TestReachableInAORDoesNotSignBeforeFallbackCondition
TestFallbackSigningRechecksReachabilityAndRadius
TestWarmupDoesNotTriggerFallbackReceipt
TestContextCancellationDoesNotTriggerFallbackReceipt
TestReachabilityFlipAllowsFallbackOnlyAtSigningTime
TestReachableInAORReturnsDownstreamReceiptBeforeFallback
TestFallbackTimeoutResetsWhenDownstreamSendStarts
TestFallbackDoesNotCancelStartedDownstreamPush
TestErrWantSelfWithOverdraftWaitsBeforeFallbackReceipt
TestErrNotFoundKeepsBroadOverdraftRefreshForOrigin
TestHandlerDeliveredInAORChunkWithNoPeersUnwrapsOnce
```

The lazy-signing test could use a signer spy that fails if `Sign` is called before a fallback condition is reached. The unwrap regression test could use an unwrap spy and a reachable in-AOR full node with no connected peers; the expected count is exactly one.

### Part 2 - Reporting, metrics, and regression coverage

This part should not change Pushsync routing logic.

`bee#5390` already adds `ChunkCouldNotSync` handling in the upload store. The remaining pusher concern is metric accuracy: a chunk reported as `ChunkCouldNotSync` must not also increment `TotalSynced`.

The pusher should track a small internal outcome for each attempt:

```text
repeat
synced
stored locally
could not sync
error
```

Only `synced` and `stored locally` should increment synced counters. `could not sync` should increment the failure metric and must not be reported as successful sync.

This part should also add or verify metrics for in-AOR forwarding attempts, fallback receipts, `ErrWantSelf` overdraft waits, and chunks that could not sync.

Suggested tests for Part 2:

```text
TestCouldNotSyncDoesNotIncrementTotalSynced
TestDeferredUploadReportsCouldNotSyncOnFinalFailure
TestDirectUploadKeepsShallowReceiptAsError
TestStorerForwardAttemptMetric
TestStorerFallbackReceiptMetric
TestOverdraftRefreshMetricForErrWantSelf
```

## Conclusion

A full in-AOR node should protect the upload by storing locally, but it should not end the push path before the closest selectable reachable candidate has had a fair chance to receive the chunk. Local receipts should be lazy, bounded fallbacks for currently reachable full in-AOR nodes only.

This keeps Pushsync easier to reason about, avoids premature `ErrWantSelf` decisions during overdraft refresh, prevents duplicate local delivery on the no-peer fallback path, and complements the silent-loss fixes in `bee#5390`.
