# SWIPs
Swarm Improvement Proposals (SWIPs) describe standards for the Swarm platform, including core protocol 
specifications, client APIs, and contract standards.

A browsable version of all current and draft SWIPs can be found on [GitHub](https://github.com/ethersphere/SWIPs).
<!-- TODO: This must be Swarm site eventually -->

# Contributing

 1. Review [SWIP-0](SWIPs/swip-0.md).
 2. Fork the repository by clicking "Fork" in the top right.
 3. Add your SWIP to your fork of the repository. There is a [template SWIP here](SWIPs/swip-X.md).
 4. Submit a Pull Request to Swarm's [SWIPs repository](https://github.com/ethersphere/SWIPs).

Your first PR should be a first draft of the final SWIP. It must meet the formatting criteria. An editor will manually review the 
first PR for a new SWIP and assign it a number before merging it. Make sure you include a `discussions-to` header with the URL to 
a discussion forum or open GitHub issue where people can discuss the SWIP as a whole.

If your SWIP requires images, the image files should be included in a subdirectory of the `assets` folder for that SWIP as 
follows: `assets/swip-X` (for swip **X**). When linking to an image in the SWIP, use relative links such as 
`../assets/swip-X/image.png`.

When you believe your SWIP is mature and ready to progress past the draft phase, you should open a PR changing the state of your 
SWIP to 'Final'. An editor will review your draft and ask if anyone objects to its being finalised. If the editor decides there 
is no rough consensus - for instance, because contributors point out significant issues with the SWIP - they may close the PR and 
request that you fix the issues in the draft before trying again.

# SWIP Status Terms

* **Draft** - a SWIP that is undergoing rapid iteration and changes.
* **Last Call** - a SWIP that is done with its initial iteration and ready for review by a wide audience.
* **Accepted** - a core SWIP that has been in Last Call for at least 2 weeks and any technical changes that were requested have been addressed by the author. The process for Core Devs to decide whether to encode a SWIP into their clients as part of a mandatory update is not part of the SWIP process. If such a decision is made, the SWIP will move to final.
* **Final (non-Core)** - a SWIP that has been in Last Call for at least 2 weeks and any technical changes that were requested have been addressed by the author.
* **Final (Core)** - a SWIP that the Core Devs have decided to implement and release in a future mandatory update or has already been released as such. 
* **Deferred** - a SWIP that is not being considered for immediate adoption. May be reconsidered in the future.


