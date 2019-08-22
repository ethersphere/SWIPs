---
SWIP: <to be assigned>
title: HTTP API
author: <a list of the author's or authors' name(s) and/or username(s), or name(s) and email(s), e.g. (use with the parentheses or triangular brackets): Viktor Trón, (@zelig) <viktor@ethswarm.org>, Daniel Nagy (@nagydani), <daniel@ethswarm.org>, Tim Bansemer (editorial) (@FantasticoFox) <tim@ethswarm.org>
discussions-to: https://swarmresear.ch/
status: Draft
type: Standards Track Interface 
created: 2019-11-07
---

## Simple Summary
<!--"If you can't explain it simply, you don't understand it well enough." Provide a simplified and layman-accessible explanation of the SWIP.-->
Description of a HTTP-based API through which Swarm nodes can be accessed locally. Also forms the basis of web gateway specification.

## Abstract
<!--A short (~200 word) description of the technical issue being addressed.-->
The HTTP API is the primary API through which applications and client software access data stored in Swarm. It provides access to two separate layers of Swarm, the `raw` layer storing binary blobs of arbitrary size without further metadata and the manifest-described virtual web server, turning Swarm collections identified by the root hash of their manifests, possibly registered in ENS, into virtual static web servers. Furthermore, it provides transparent access to *Swarm encryption* and *access control*.

## Motivation
<!--The motivation is critical for SWIPs that want to change the Swarm protocol. It should clearly explain why the existing protocol specification is inadequate to address the problem that the SWIP solves. SWIP submissions without sufficient motivation may be rejected outright.-->

As Swarm is part of the strategy to radically decentralize the World Wide Web, it is essential to maintain as much compatibility with existing web standards as allowed by the substantial difference between Swarm's peer-to-peer model and the World Wide Web's client-server model. This API intends to mimic the API of `http`/`https` servers as closely as possible from the application developers perspective.

## Specification
<!--The technical specification should describe the syntax and semantics of any new feature. The specification should be detailed enough to allow competing, interoperable implementations for the current Swarm platform and future client implementations.-->

The table below contains an exhaustive list of `HTTP` request and expected `HTTP` response specifications. Nodes that are not set up as Web gateways, should only respond to locally originating requests. Servicing some of these requests might incure costs to the node, so appropriate access control is essential to the security of the node.

<table>
<col width="4%" />
<col width="2%" />
<col width="4%" />
<col width="89%" />
<thead>
<tr class="header">
<th align="left">Name</th>
<th align="left">Method</th>
<th align="left">Descriptors</th>
<th align="left"></th>
</tr>
</thead>
<tbody>
<tr class="odd">
<td align="left">bzz</td>
<td align="left">GET</td>
<td align="left">Purpose</td>
<td align="left">retrieve document at domain/some/path allowing domain to resolve via the Ethereum Name Service</td>
</tr>
<tr class="even">
<td align="left"></td>
<td align="left"></td>
<td align="left">Locator</td>
<td align="left">bzz:/&lt;domain_part&gt;/&lt;resource_path&gt;</td>
</tr>
<tr class="odd">
<td align="left"></td>
<td align="left"></td>
<td align="left">Locator Parts</td>
<td align="left">domain part: mandatory - ENS name or a valid Swarm hash. path part: optional - a case insensitive path to match for in the manifest</td>
</tr>
<tr class="even">
<td align="left"></td>
<td align="left"></td>
<td align="left">HTTP Codes</td>
<td align="left">200; 300; 404; 500</td>
</tr>
<tr class="odd">
<td align="left"></td>
<td align="left"></td>
<td align="left">Responds with</td>
<td align="left">The content stored at the resolved ENS entry (or the matched path) with the appropriate Content-Type as stored in the manifest</td>
</tr>
<tr class="even">
<td align="left"></td>
<td align="left"></td>
<td align="left">Example</td>
<td align="left"></td>
</tr>
<tr class="odd">
<td align="left"></td>
<td align="left">POST</td>
<td align="left">Purpose</td>
<td align="left">post an application/x-tar or multipart/form-data (or any other Content-Type for that matter); create an appropriate manifest and retrieve the associated hash. if an existing manifest address is given with the according path to update - a copy of the manifest will be created with the updated entry and the hash of the new manifest will be returned</td>
</tr>
<tr class="even">
<td align="left"></td>
<td align="left"></td>
<td align="left">Locator</td>
<td align="left">bzz:/&lt;manifest_hash?&gt;/&lt;resource_path?&gt;/&lt;encrypt?&gt;</td>
</tr>
<tr class="odd">
<td align="left"></td>
<td align="left"></td>
<td align="left">Locator Parts</td>
<td align="left">manifest hash - optional - an existing manifest address to update a resource included in the manifest. resource path - optional - which resource to update in the manifest. encrypt - optional flag to enable encryption</td>
</tr>
<tr class="even">
<td align="left"></td>
<td align="left"></td>
<td align="left">HTTP Codes</td>
<td align="left">200</td>
</tr>
<tr class="odd">
<td align="left"></td>
<td align="left"></td>
<td align="left">Responds with</td>
<td align="left">a hash of a newly created manifest</td>
</tr>
<tr class="even">
<td align="left"></td>
<td align="left"></td>
<td align="left">Example</td>
<td align="left"></td>
</tr>
<tr class="odd">
<td align="left"></td>
<td align="left">DELETE</td>
<td align="left">Purpose</td>
<td align="left">delete a resource from a manifest by unlinking it from the existing manifest</td>
</tr>
<tr class="even">
<td align="left"></td>
<td align="left"></td>
<td align="left">Locator</td>
<td align="left">bzz:/&lt;domain&gt;/&lt;path&gt;</td>
</tr>
<tr class="odd">
<td align="left"></td>
<td align="left"></td>
<td align="left">Locator Parts</td>
<td align="left">domain part - mandatory - a valid ENS hash or a valid Swarm manifest hash. path part - mandatory - a path to the resource to be removed from the manifest</td>
</tr>
<tr class="even">
<td align="left"></td>
<td align="left"></td>
<td align="left">HTTP Codes</td>
<td align="left">200; 404; 500</td>
</tr>
<tr class="odd">
<td align="left"></td>
<td align="left"></td>
<td align="left">Responds with</td>
<td align="left">the hash of the new manifest which does not have component <code>path</code></td>
</tr>
<tr class="even">
<td align="left"></td>
<td align="left"></td>
<td align="left">Example</td>
<td align="left"></td>
</tr>
<tr class="odd">
<td align="left">bzz-immutable</td>
<td align="left">GET</td>
<td align="left">Purpose</td>
<td align="left">The same as the generic scheme but there is no ENS domain resolution. the domain part of the path needs to be a valid hash. This is also a read-only scheme but explicit in its integrity protection. A particular bzz-immutable url will always necessarily address the exact same fixed immutable content.</td>
</tr>
<tr class="even">
<td align="left"></td>
<td align="left"></td>
<td align="left">Locator</td>
<td align="left">bzz-immutable:/&lt;hash&gt;</td>
</tr>
<tr class="odd">
<td align="left"></td>
<td align="left"></td>
<td align="left">Locator Parts</td>
<td align="left">hash part - a valid Swarm hash that points to a manifest</td>
</tr>
<tr class="even">
<td align="left"></td>
<td align="left"></td>
<td align="left">HTTP Codes</td>
<td align="left">200; 404; 500</td>
</tr>
<tr class="odd">
<td align="left"></td>
<td align="left"></td>
<td align="left">Responds with</td>
<td align="left">the resolved content at the specified address with a valid content-type as stored in the manifest</td>
</tr>
<tr class="even">
<td align="left"></td>
<td align="left"></td>
<td align="left">Example</td>
<td align="left">use bzz-hash to resolve the ens name into a hash then use it with immutable</td>
</tr>
<tr class="odd">
<td align="left">bzz-raw</td>
<td align="left">GET</td>
<td align="left">Purpose</td>
<td align="left">When responding to GET requests with the bzz-raw scheme swarm does not assume a manifest but just serves the asset addressed by the url directly. The <code>content_type</code> query parameter can be supplied to specify the mime type you are requesting otherwise content is served as an octet stream per default.</td>
</tr>
<tr class="even">
<td align="left"></td>
<td align="left"></td>
<td align="left">Locator</td>
<td align="left">bzz-raw:/&lt;content_hash&gt;?content_type=&lt;mime&gt;</td>
</tr>
<tr class="odd">
<td align="left"></td>
<td align="left"></td>
<td align="left">Locator Parts</td>
<td align="left">content hash - mandatory - a valid Swarm content hash. content type - optional - the mime type to serve the content as. defaults to application/octet-stream</td>
</tr>
<tr class="even">
<td align="left"></td>
<td align="left"></td>
<td align="left">HTTP Codes</td>
<td align="left">200; 404; 500</td>
</tr>
<tr class="odd">
<td align="left"></td>
<td align="left"></td>
<td align="left">Responds with</td>
<td align="left"></td>
</tr>
<tr class="even">
<td align="left"></td>
<td align="left"></td>
<td align="left">Example</td>
<td align="left">a pdf document (not the manifest wrapping it) resides at hash 6a182226... then the following url will properly serve it: GET <a href="http://localhost:8500/bzz-raw:/6a18222637cafb4ce692fa11df886a03e6d5e63432c53cbf7846970aa3e6fdf5?content_type=application/pdf">http://localhost:8500/bzz-raw:/6a18222637cafb4ce692fa11df886a03e6d5e63432c53cbf7846970aa3e6fdf5?content_type=application/pdf</a></td>
</tr>
<tr class="odd">
<td align="left"></td>
<td align="left">POST</td>
<td align="left">Purpose</td>
<td align="left"></td>
</tr>
<tr class="even">
<td align="left"></td>
<td align="left"></td>
<td align="left">Locator</td>
<td align="left"></td>
</tr>
<tr class="odd">
<td align="left"></td>
<td align="left"></td>
<td align="left">Locator Parts</td>
<td align="left"></td>
</tr>
<tr class="even">
<td align="left"></td>
<td align="left"></td>
<td align="left">HTTP Codes</td>
<td align="left">200; 404; 500</td>
</tr>
<tr class="odd">
<td align="left"></td>
<td align="left"></td>
<td align="left">Responds with</td>
<td align="left"></td>
</tr>
<tr class="even">
<td align="left"></td>
<td align="left"></td>
<td align="left">Example</td>
<td align="left"></td>
</tr>
<tr class="odd">
<td align="left">bzz-list</td>
<td align="left">GET</td>
<td align="left">Purpose</td>
<td align="left">Returns a list of all files contained in &lt;manifest&gt; under &lt;path&gt; grouped into common prefixes using <code>/</code> as a delimiter. If path is <code>/</code> - all files in manifest are returned. The response is a JSON-encoded object with <code>common_prefixes</code> string field and <code>entries</code> list field.</td>
</tr>
<tr class="even">
<td align="left"></td>
<td align="left"></td>
<td align="left">Locator</td>
<td align="left">bzz-list:/&lt;domain&gt;/&lt;path&gt;</td>
</tr>
<tr class="odd">
<td align="left"></td>
<td align="left"></td>
<td align="left">Locator Parts</td>
<td align="left">domain part - mandatory - a valid ENS entry that points to a valid manifest hash or a valid manifest hash. path part - optional - path to look for inside the manifest</td>
</tr>
<tr class="even">
<td align="left"></td>
<td align="left"></td>
<td align="left">HTTP Codes</td>
<td align="left">200; 404; 500</td>
</tr>
<tr class="odd">
<td align="left"></td>
<td align="left"></td>
<td align="left">Responds with</td>
<td align="left"></td>
</tr>
<tr class="even">
<td align="left"></td>
<td align="left"></td>
<td align="left">Example</td>
<td align="left"></td>
</tr>
<tr class="odd">
<td align="left">bzz-hash</td>
<td align="left">GET</td>
<td align="left">Purpose</td>
<td align="left">responds with the hash value of the raw content - the same content returned by requests with bzz-raw scheme. Hash of the manifest is also the hash stored in ENS so bzz-hash can be used for ENS domain resolution</td>
</tr>
<tr class="even">
<td align="left"></td>
<td align="left"></td>
<td align="left">Locator</td>
<td align="left">bzz-hash:/&lt;domain&gt;</td>
</tr>
<tr class="odd">
<td align="left"></td>
<td align="left"></td>
<td align="left">Locator Parts</td>
<td align="left">domain part - mandatory. a valid ENS name</td>
</tr>
<tr class="even">
<td align="left"></td>
<td align="left"></td>
<td align="left">HTTP Codes</td>
<td align="left">200; 404; 500</td>
</tr>
<tr class="odd">
<td align="left"></td>
<td align="left"></td>
<td align="left">Responds with</td>
<td align="left">text/plain</td>
</tr>
<tr class="even">
<td align="left"></td>
<td align="left"></td>
<td align="left">Example</td>
<td align="left"></td>
</tr>
<tr class="odd">
<td align="left">bzz-feed</td>
<td align="left">GET</td>
<td align="left">Purpose</td>
<td align="left">Retrieve a Feed update</td>
</tr>
<tr class="even">
<td align="left"></td>
<td align="left"></td>
<td align="left">Locator</td>
<td align="left">bzz-<a href="feed:/">feed:/</a>&lt;hash&gt;?user=&lt;user&gt;&amp;topic=&lt;topic&gt;&amp;name=&lt;name&gt;&amp;time=&lt;t&gt;</td>
</tr>
<tr class="odd">
<td align="left"></td>
<td align="left"></td>
<td align="left">Locator Parts</td>
<td align="left">hash - optional - manifest hash of the Feed, otherwise user param required. user - optional - Ethereum address of the user who publishes the Feed. topic - optional - Feed topic, encoded as a hex string, default: 0. name - optional - subtopic that is combined with the topic, default: &quot;&quot;. time - optional - The last update before that time (unix time) will be looked up, default: most recent update. meta - optional - Just return the Feed metadata, default 0 (false).</td>
</tr>
<tr class="even">
<td align="left"></td>
<td align="left"></td>
<td align="left">HTTP Codes</td>
<td align="left">200; 400; 404; 500</td>
</tr>
<tr class="odd">
<td align="left"></td>
<td align="left"></td>
<td align="left">Responds with</td>
<td align="left">The content stored in the requested Feed update</td>
</tr>
<tr class="even">
<td align="left"></td>
<td align="left"></td>
<td align="left">Example</td>
<td align="left"></td>
</tr>
<tr class="odd">
<td align="left"></td>
<td align="left">GET</td>
<td align="left">Purpose</td>
<td align="left">Get Feed metadata, used to help publishing updates</td>
</tr>
<tr class="even">
<td align="left"></td>
<td align="left"></td>
<td align="left">Locator</td>
<td align="left">bzz-<a href="feed:/">feed:/</a>&lt;hash&gt;?user=&lt;user&gt;&amp;topic=&lt;topic&gt;&amp;name=&lt;name&gt;&amp;meta=1</td>
</tr>
<tr class="odd">
<td align="left"></td>
<td align="left"></td>
<td align="left">Locator Parts</td>
<td align="left">hash - optional - manifest hash of the Feed, otherwise user param required. user - optional - Ethereum address of the account that owns the Feed. topic - optional - Feed topic, encoded as a hex string, default: 0. name - optional - subtopic that is combined with the topic, default: &quot;&quot;. meta - required - Return the Feed metadata instead of the Feed content.</td>
</tr>
<tr class="even">
<td align="left"></td>
<td align="left"></td>
<td align="left">HTTP Codes</td>
<td align="left">200; 400; 500</td>
</tr>
<tr class="odd">
<td align="left"></td>
<td align="left"></td>
<td align="left">Responds with</td>
<td align="left">application/json</td>
</tr>
<tr class="even">
<td align="left"></td>
<td align="left"></td>
<td align="left">Example</td>
<td align="left"></td>
</tr>
<tr class="odd">
<td align="left"></td>
<td align="left">POST</td>
<td align="left">Purpose</td>
<td align="left">Post an update to a Feed</td>
</tr>
<tr class="even">
<td align="left"></td>
<td align="left"></td>
<td align="left">Locator</td>
<td align="left">bzz-<a href="feed:/">feed:/</a>&lt;hash&gt;?user=&lt;user&gt;&amp;topic=&lt;topic&gt;&amp;level=&lt;level&gt;&amp;time=&lt;time&gt;&amp;protocolVersion=&lt;ver&gt;&amp;signature=&lt;sig&gt;</td>
</tr>
<tr class="odd">
<td align="left"></td>
<td align="left"></td>
<td align="left">Locator Parts</td>
<td align="left">hash - optional - manifest hash of the Feed, otherwise user param required. user - optional - Ethereum address of the account that owns the Feed. topic - optional - Feed topic, encoded as a hex string, default: 0. level - optional - suggested frequency level (retreived above). time - optional - suggested timestamp (retrieved above). protocolVersion - optional - Feed protocol version, default: current version. signature - required - Feed signature hex encoded</td>
</tr>
<tr class="even">
<td align="left"></td>
<td align="left"></td>
<td align="left">HTTP Codes</td>
<td align="left">200; 400; 500</td>
</tr>
<tr class="odd">
<td align="left"></td>
<td align="left"></td>
<td align="left">Responds with</td>
<td align="left"></td>
</tr>
<tr class="even">
<td align="left"></td>
<td align="left"></td>
<td align="left">Example</td>
<td align="left"></td>
</tr>
</tbody>
</table>

## Rationale
<!--The rationale fleshes out the specification by describing what motivated the design and why particular design decisions were made. It should describe alternate designs that were considered and related work, e.g. how the feature is supported in other languages. The rationale may also provide evidence of consensus within the community, and should discuss important objections or concerns raised during discussion.-->
The URI endpoints are set up in such a way that a standard [http protocol handler](https://developer.mozilla.org/en-US/docs/Web/API/Navigator/registerProtocolHandler) can be used to service them as separate protocols. Even though some browsers restrict protocol handlers to a whitelist, `bzz:` and the rest can be included in that whitelist in the future, as Swarm's popularity grows.

## Backwards Compatibility
<!--All SWIPs that introduce backwards incompatibilities must include a section describing these incompatibilities and their severity. The SWIP must explain how the author proposes to deal with these incompatibilities. SWIP submissions without a sufficient backwards compatibility treatise may be rejected outright.-->
Since Swarm has a serverless architecture, the only web applications -- including Web3 -- that can be expected to work without any modification on Swarm via the HTTP API are those that have no server-side component, implementing all business logic in the client.

## Test Cases
<!--Test cases for an implementation are mandatory for SWIPs that are affecting changes to data and message formats. Other SWIPs can choose to include links to test cases if applicable.-->


## Implementation
<!--The implementations must be completed before any SWIP is given status "Final", but it need not be completed before the SWIP is accepted. While there is merit to the approach of reaching consensus on the specification and rationale before writing code, the principle of "rough consensus and running code" is still useful when it comes to resolving many discussions of API details.-->
The definitive implementation of Swarm http API is the `swarm` client written in golang.

## Copyright
Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
