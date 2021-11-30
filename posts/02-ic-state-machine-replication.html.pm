#lang pollen

◊(define-meta title "A swarm of replicated state machines")
◊(define-meta keywords "ic")
◊(define-meta summary "Let's look at the Internet Computer through the lens of state machine replication.")
◊(define-meta doc-publish-date "2021-11-10")
◊(define-meta doc-updated-date "2021-11-10")

◊p{
In this article, we shall view the Internet Computer (IC) through the lens of distributed system design.
As most other blockchains, the IC achieves fault-tolerance using strategy called ◊a[#:href "https://en.wikipedia.org/wiki/State_machine_replication"]{state machine replication}.
We shall take a close look at some design choices that make the IC fast, scalable, and secure.
}

◊section["state-machine"]{The state machine}

◊p{
Before we dive into the internals of the protocol, let's first define the ◊a[#:href "https://en.wikipedia.org/wiki/Finite-state_machine"]{state machine} that we'll be dealing with.
Nodes participating in the Internet Computer are grouped into units called ◊em{subnets}.
Nodes in the same subnet run their own instance of the consensus protocol.
We'll model as a state machine the computation that nodes in the same subnet perform.
}
◊p{
Let's play by the book and define components of our state machine:
}
◊dl{
◊dt{Inputs}
◊dd{The key product of the consensus protocol is a sequence of blocks containing messages for canisters hosted by the subnet. These blocks are the inputs of our state machine.}
◊dt{Outputs}
◊dd{In our model, the main artifact of the execution is a data structure called ◊em{state tree}.
We'll learn more about state trees in a moment.}
◊dt{States}
◊dd{
The single most important thing that the Internet Computer does is hosting canisters.
Thus we'll define the state as a data structure containing everything we need to serve canisters installed on the subnet, including but not limited to:
◊ul[#:class "arrows"]{
◊li{◊a[#:href "https://webassembly.org/"]{WebAssembly} modules and configuration of the canisters.}
◊li{Memory and stable memory of those canisters.}
◊li{Messages in canister mailboxes.}
◊li{Results of the recent ingress messages.}
}
}
◊dt{Transition function}
◊dd{When a replica receives a block, it
  ◊ul[#:class "arrows"]{
  ◊li{Injects messages from the block into the canister mailboxes.}
  ◊li{Picks some canisters for execution according to a deterministic scheduling algorithm.}
  ◊li{Executes the messages on the selected canisters and records the execution results.}
  }
  All of the above modifies the data structure that we call "state" and acts as a transition function.
  Note that we can call this procedure a ◊em{function} only if it's deterministic: given the same block and the same original state, the replica will modify the state in exactly the same way.
  Thanks to the careful design of execution algorithms and guarantees that WebAssembly provides, the procedure is indeed deterministic.
}
◊dt{Output function}
◊dd{Once a replica processed a block, it computes a state tree.
This tree can be used to inspect the results of the execution and validate the authenticity of those results.}
◊dt{Initial state}
◊dd{
Each subnet starts its life with no canisters, no messages, and no results to inspect.
It's as boring as it gets.
}
}

I call these state machines (one for each subnet) ◊em{replicated} because each honest node on a subnet has an exact copy of the machine.

◊subsection["checkpoints"]{Checkpoints}
◊p{
Let's say we want to add a new node to an existing subnet because a flood destroyed one of the data centers hosting the subnet.
This new node cannot start processing and proposing new blocks until it has the right state, the state that results from execution of all the blocks produced by this subnet so far.
}
◊p{
One way to bring the node up to date is to download all those blocks and "replay" them.
This sounds simple, but if the rate of change is high and message execution is costly, the new node might need a ◊em{lot} of time to catch up.
As the Red Queen put it: “My dear, here we must run as fast as we can, just to stay in place.
And if you wish to go anywhere you must run twice as fast as that.”
}
◊p{
Another solution is to create persistent snapshots of the state from time to time.
The peers can fetch and load those snapshots when they need help.
This method works really well for our state machine: it reduces the catch up time from days to minutes.
Let's call those persistent snapshots ◊em{checkpoints}.
}

◊figure[#:class "grayscale-diagram"]{
◊p{◊(embed-svg "images/02-states.svg")}
}

◊section["threshold-signatures"]{Threshold signatures}
◊p{
The state machine relies on ◊em{threshold signatures} for constructing proofs of data authenticity.
Let's take a quick look at this technology, which lies at the heart of ◊a[#:href "https://dfinity.org/howitworks/chain-key-technology"]{chain key technology}.
}
◊p{
The idea is relatively simple: we require nodes to collaborate to construct cryptographic signatures in such a way that ⅔ of the subnet nodes must sign the same data for the signature to be valid.
The implementation relies on ◊a[#:href "https://en.wikipedia.org/wiki/Public-key_cryptography"]{Public-key cryptography}.
}
◊p{
Imagine that we have a box with an asymmetric lock: only the owner of a special secret key can lock it.
The key opening the box is public.
If you receive a locked box, open it and get a letter, you can be sure that the person who put the letter into that box had the private key.
This is analogous to how simple digital signatures work.
Note, however, that our analogy is imperfect: unlike physical locked boxes, digital signatures can be copied perfectly.
}
◊p{
Threshold signatures add a slight twist to the setup: let's say we want four parties to collaborate on a document, and we want to be sure that at least three of those parties agreed on the contents.
We construct a fancier box that has six locks on it and distribute sets of locking keys among the participants.
Each participant gets three keys in such a way that at least three parties have to use their sets of keys for the box to be fully locked.
One possible arrangement of key sets is depicted below.
}

◊figure[#:class "grayscale-diagram"]{
◊p{◊(embed-svg "images/02-key-shares.svg")}
}

◊p{
As before, anyone can unlock the box.
If you get a fully locked box, you can be sure that the majority of the participants agreed on the contents of the document inside that box.
}

◊p{
The sets of keys in our analogy are called ◊em{key shares}.
The public set of keys opening all the locks is called ◊em{subnet key} or ◊em{chain key}.
Replicas use a secure protocol to distribute key shares among the nodes, but we won't dive into details of this protocol.
}

◊p{
In this article we'll also use term ◊em{certification} of some value X, which means collecting a threshold signature for a cryptographic hash of X (or the root hash of a merkle tree containing X).
}

◊section["state-trees"]{State trees}
◊p{
The procedure that we called a transition function is complex, but all its details aren't very important for our discussion.
We can treat block processing as a black box.
Let's now take a look at how we get the data out of the state machine.
}

◊p{
There are quite a few bits of information that we want to get back from the state machine, for example:
}
◊ul[#:class "arrows"]{
◊li{Replies to user requests.}
◊li{Canister metadata, like module hashes or certified data entries.}
◊li{Messages that cannot be processed by this subnet and need to be routed to other state machines.}
}
◊p{
Furthermore, because we cannot trust any particular node, we want to have some authenticity guarantees for the data we get back.
Sounds easy: compute all interesting bits hash of the state, collect a threshold signature on it, and use the signature as a proof of state authenticity.
}
◊p{
But how do can we validate a single request status if we have a signature on the full state?
Collecting a separate signature for each request would solve the problem, but the cost of this approach is unacceptable from the performance point of view.
}
◊p{
Wouldn't it be great to be able to "zoom" into different parts of the state for different clients, while still having only a single hash to sign?
Enter state trees.
}


◊figure[#:class "grayscale-diagram"]{
◊p{◊(embed-svg "images/02-state-tree.svg")}
}

◊p{
State tree is a data structure that contains all outputs of our state machine in a form of a ◊a[#:href "https://en.wikipedia.org/wiki/Merkle_tree"]{merkle tree}.
Once the gears of the execution stopped, the system computes the root hash of the state tree corresponding to the new state, initiates the process of certification for that hash, and moves on to the next block.
}

◊subsection["tree-lookup"]{Lookup}
◊p{
Let's look at an example to see how the state tree does its magical zooming.
Assume that you sent a request with id ◊code{1355...48de} to the IC and you want to get back the reply.
As we now know, the system will put the reply into a state tree, so let's make a ◊code{read_state} request with path ◊code{"/request_status/1355...48de/reply"}.
}
◊p{The replica processes your request in the following way}
◊ol-circled{
  ◊li{Check that the caller has permissions to look at the paths listed in the ◊code{read_state} request.}
  ◊li{Get the latest certified state tree.}
  ◊li{Make the result tree that includes all the paths from the ◊code{read_state} request, with all the pruned branches replaced by their hashes.}
  ◊li{Combine the result tree with the threshold signature to form a full certified reply.}
}
◊p{
The tree that you'll get back will look something like this:
}

◊figure[#:class "grayscale-diagram"]{
◊p{ ◊(embed-svg "images/02-pruned-state-tree.svg") }}

◊p{
Even though the pruned tree is much smaller than the full state tree, both trees have exactly the same root hash.
So we can validate the authenticity of the pruned tree using the threshold signature that consensus collected for the root hash of the full state tree.
}

◊section["state-transfer"]{State transfer}

◊subsection["state-artifact"]{State as an artifact}
◊p{
As we discussed in the ◊a[#:href "#checkpoints"]{checkpoints} section, a replica periodically persists snapshots of its state to disk.
The main purpose of these snapshots is to speed up state recovery.
If a replica was out for a brief period of time, it can use its own checkpoint to recover more quickly than replaying all the blocks starting from genesis.
Load the checkpoint, replay a few blocks, and you're ready to rock.
There is a more interesting case, however: a healthy replica can help other replicas catch up by sending them a recent checkpoint.
}
◊p{
Replicas in a subnet communicate by exchanging ◊em{artifacts} using a peer-to-peer protocol.
Most of these artifacts (e.g., user ingress messages, random beacons, state certifications) are relatively small, up to a few megabytes in size.
But the machinery for artifact transfer is quite general: the protocol supports fetching arbitrary large artifacts by slicing them into chunks, provided that there is a way to authenticate each chunk independently.
Furthermore, multiple chunks can be fetched in parallel from multiple peers.
If this reminded you of ◊a[#:href "https://en.wikipedia.org/wiki/BitTorrent"]{BitTorrent}, you got the right idea.
}
◊p{
Before advertising a checkpoint, replica computes a ◊em{manifest} for that checkpoint.
Manifest is an inventory of files constituting a checkpoint.
Files are sliced into chunks, and the manifest enumerates paths, sizes and cryptographic hashes of every file and every chunk of each file.
In our BitTorrent analogy, manifest plays a role of a ◊a[#:href "https://en.wikipedia.org/wiki/Torrent_file"]{.torrent file}.
If we have a manifest, we know for sure how much data we need to fetch to construct a checkpoint, and how to arrange this data.
Hashes of file chunks in the manifest allow us to validate each chunk independently before we put it to disk.
Replicas use the hash of the manifest in artifact advertisements they send through the peer-to-peer network.
}

◊figure[#:class "grayscale-diagram"]{
◊p{ ◊(embed-svg "images/02-checkpoint-artifact.svg") }
}

◊subsection["trigger-transfer"]{Triggering state transfer}
◊p{
Let's assume that we add a new replica to a subnet, and that replica needs to fetch the latest checkpoint.
It listens to the peers, and discovers a few state artifacts with different hashes advertised by different peers.
How does our poor replica decide which state it needs to fetch?
}

◊p{
As you might have guessed, the consensus subsystem armed with ◊a[#:href "#threshold-signatures"]{threshold signatures} comes to the rescue again.
Replicas gather a threshold signature on a full state hash and use that signature as a proof of checkpoint authenticity.
The result is an artifact containing a state height, a full state hash, and a threshold signature.
We'll call this artifact a ◊em{catch-up package}.
}
◊p{
The interaction between the replica consensus module and the state machine is something like the following
}
◊ol-circled{
◊li{
Consensus sees a catch-up package for state 100 with a valid threshold signature and the state hash is ◊code{H◊sub{100}}.
Consensus asks the state machine "Hey, what's your state height?".
}
◊li{State machine: "It's nine. Why?".}
◊li{Consensus: "We're missing out. Fetch a checkpoint for state 100, but only if it has root hash ◊code{H◊sub{100}}."}
◊li{State machine: "Sure, I'm on it." The state machine starts looking for state artifact advertisements with a matching hash.}
}
◊p{Yes, the consensus module can be a bit bossy sometimes.}

◊subsection["incremental-sync"]{Fetching states incrementally}
◊p{
Let's now have a brief look at the most juicy part of state transfer, the actual state fetch protocol.
Let's suppose that we have a replica that has state 9 and it wants to catch up to state 100 with hash ◊code{H}.
}
◊ol-circled{
◊li{The replica receives advertisements for checkpoint artifacts from other peers and picks the peers that advertize the state with the hash ◊code{H}.}
◊li{The replica fetches the manifest of checkpoint 100 from one of the peers and validates that the manifest hash is indeed ◊code{H}.}
◊li{The replica compares the manifest of checkpoint 9 that it has locally to the manifest of checkpoint 100.}
◊li{
The replica copies all the chunks with the matching hashes from the old checkpoint into the new one.
Why waste network bandwidth and fetch data you already have?
}
◊li{The replica fetches all the missing chunks from the peers, validates them against the manifest, and puts on disk them where they belong.}
}
◊p{When there are no more chunks to fetch, checkpoint 100 is complete, and the replica is ready to go.}
◊figure[#:class "grayscale-diagram"]{
◊p{◊(embed-svg "images/02-state-sync.svg")}
}
◊p{
As you can see, the state synchronization procedure is incremental: if the node was offline for a brief period of time, it only needs to fetch data that actually changed in the meantime.
If the replica that is trying to catch up has no checkpoints at all, it will have to fetch all the chunks.
}

◊section["conclusion"]{Conclusion}
◊p{
In this article, we
}
◊ul[#:class "arrows"]{
◊li{◊a[#:href "#state-machine"]{Abstracted} the complexity of block execution into a transition function of a finite state machine.}
◊li{Marveled at how ◊a[#:href "#state-trees"]{state trees} and ◊a[#:href "#threshold-signatures"]{threshold signatures} allow clients retrieve authentic replies by consulting only one replica.}
◊li{Learned how replicas can their transfer states ◊a[#:href "#incremental-sync"]{quickly} and ◊a[#:href "#trigger-transfer"]{securely}.}
}
◊p{
This concludes our overview of how the IC implements state machine replication on the scale of a single subnet.
From that prospective, the IC as a whole is really a swarm of replicated state machines!
}
◊p{
I made a few simplifications and omitted a lot of details to keep us focused on the replication aspect.
For example, we didn't look at how different subnets communicate with one another, how individual worker bees form the swarm.
This is a great topic that deserves an article of its own, so stay tuned!
}
