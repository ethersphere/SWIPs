---
SWIP: <To be assigned>
title: Swarm node implementer spec - Chunk and hasher
author: Louis Holbrook <dev@holbrook.no> (https://holbrook.no)
status: Draft
type: Track Specs
created: 2019-09-14
---

## Abstract

This SWIP is a part of a general specification of a Swarm node. The SWIP system is used for convenience only.

## Motivation

Enable other implementations of the swarm node.

## Backwards Compatibility

N/A

## Test Cases

N/A

## Implementation

N/A

## Copyright

Copyright and related rights waived via CC0

## Specification

Data stored in Swarm consists of \texttt{Chunks}.

\subsection{Chunk Size}

The size of a chunk is the digest size of the \texttt{Base Hash} multiplied by an arbitary exponential of 2. Currently the size is defined as 4096 bytes \footnote{$2^7 * 32$}

\subsection{Chunk Reference}

The Chunk storage in Swarm is \emph{content addressed}. This means that the identifier of each individual \texttt{Chunk} in the store is a function of the content itself.

This identifier always contains the address of the \texttt{Chunk}. This address is a \texttt{Swarm Overlay Address}, which means that \emph{nodes} and \emph{content} have comparable identifiers. \ref{src:distance-and-proximity}.

Retrieval and interpretation of a \texttt{Chunk} from the store \emph{may} require more information than merely its identifier in the store. The entity encaspulating this information is called the \texttt{Chunk Reference}.

In its simplest form, the \texttt{Chunk Reference} is the same as the address of the \texttt{Chunk}. 

\subsection{BMT Hash}

The hashing method used to obtain the address of a \texttt{Chunk} is called the \texttt{Binary Merkle Tree Hash}, or \texttt{BMT Hash} for short.

Building this tree enables cryptographic proofs down to ``wordsize'' data units with logarithmic overhead. This ``wordsize'' is referred to as the \texttt{Segment Size}.

The \texttt{Segment Size} is the same as the digest size of the \texttt{Base Hash} used to construct the tree. This means the \texttt{Segment Size} is 32 bytes.

Note that one feature aligning data segments with their \texttt{BMT Hashes} is that one single segment may in fact \emph{either} contain verbatim data \emph{or} an address pointing to a \texttt{Chunk}.

\subsubsection{Calculating the BMT Hash}

Obtaining the \texttt{BMT Hash} of a \texttt{Chunk} involves the following steps:

\begin{enumerate}
\item If the content is shorter than the \texttt{Chunk Size} (4096 bytes), it is padded with zeros up to \texttt{Chunk Size}
\item Calculate the \texttt{Base Hash} of \emph{pairs} of \texttt{Segment Size} ($2 * 32$) units of data and concatenate the results
\item Repeat previous step on the result until the result is \texttt{Segment Size} bytes long
\item Calculate the data size represented by the unpadded data as a 64-bit little-endian integer value
\item Prepend the data size integer to the hash of the data and calculate the \texttt{Base Hash} of the data
\end{enumerate}

\subsection{Swarm Hash}

If the size of the data to be hashed is greater than the size of one \texttt{Chunk}, a multi-branched Merkle Tree of \texttt{Chunk References} is constructed to represent it.

The topmost hash of this tree is called the \texttt{Swarm Hash}. It is possible to access all relevant \texttt{Chunk References} for a particular \emph{data blob} that has been added to Swarm through the \texttt{Swarm Hash}. \footnote{This is the normal entry point for data retrieval queries. This is as close as one gets to the notion of a ``file'' in Swarm}

The number of branches the tree contains is calculated from the \texttt{Chunk Size} divided by the \texttt{Segment Size}, which currently amounts to 128. A group of 128 \texttt{Chunks} is referred to as a \texttt{Batch}.

It follows that one single \texttt{Chunk} of \texttt{BMT Hashes} may represent up to 128 individual \texttt{Chunks}. These in turn, of course, may be a chunk of hashes referring to more chunks, and so on. The size of data recursively represented by a \texttt{Chunk Reference} is called the \texttt{Chunk Span}.

\subsubsection{Intermediate Chunks} \label{sec:intermediate-chunks}

A \texttt{Chunk} containing \texttt{Chunk References} is referred to as an \texttt{Intermediate Chunk}. When calculating the \texttt{BMT Hash} of an \texttt{Intermediate Chunk}, the data size integer used in the last step of the calculation must be the \emph{actual length} of the data recursively represented by the \texttt{References}.

This table gives an overview of data sizes a \texttt{Chunk Span} can represent, depending on the level of recursion.

\begin{table}[h]
\begin{tabular}{|l|l|l|l|}
\hline
Level & Span in chunks & Span in bytes & $--human$ \\
\hline
0 (data) & 1 & 4,096 & (4KB) \\
1 & 128 & 524,288 & (500KB) \\
2 & 16,384 & 67,108,864 & (67MB) \\
3 & 2,097,152 & 8,589,934,592 & (8.5GB) \\
4 & 268,435,456 & 1,099,511,627,776 & (1.1TB) \\
5 & 34,359,738,368 & 140,737,488,355,328 & (140TB) \\
6 & 4,398,046,511,104 & 18,014,398,509,481,984 & (18PB) \\
7 & 562,949,953,421,312 & 2,305,843,009,213,693,952 & (2.3EB) \\
\hline
\end{tabular}
\caption{Some Chunk Span data size boundaries}
\end{table}

\subsubsection{Calculating the Swarm Hash}

To calculate the Swarm Hash the following method is used:

\begin{enumerate}
	\item Determine the \texttt{Chunk Reference} of each \texttt{Chunk} into an \emph{intermediate result} \footnote{Remember, use the actual size of represented data}
	\item If the $log_{128}$ of the number of \texttt{Chunks} minus one is an even number, the last \texttt{Chunk Reference} should be stored and not included in the following step
	\item Otherwise, if the $log_{128}$ of the number of \texttt{Chunks} is an even number, remove the stored \texttt{Chunk Reference} and concatenate it to the \emph{intermediate result}
	\item If the data size of the \texttt{Chunk References} of the \texttt{Chunks} (including the stored \texttt{Chunk Reference} is greater than \texttt{Segment Size}, group all the \texttt{Chunk References} in the \emph{intermediate result} and repeat from step 1 with this as the data
\end{enumerate}

Note that the \texttt{Swarm Hash} of data up to a single chunk in total size is identical to its \texttt{BMT Hash}.

\subsection{Encrypted Chunk References}

Currently, the only other defined \texttt{Chunk Reference} is used with an intra-node convenience crypto scheme.

Here all references are double the \texttt{Segment Size}. The first \texttt{Segment Size} bytes is a key to decrypt the latter \texttt{Segment Size} bytes into an actual valid address that can be retrieved from the store.

The symmetric key provided by the caller when adding the content is used as the seed to derive all decryption keys for the \texttt{Intermediate Chunks} \ref{sec:intermediate-chunks}. It is also used as the encryption key for the \texttt{Swarm Hash} \ref{sec:swarm-hash}.

\todo{Describe the crypto algo}
