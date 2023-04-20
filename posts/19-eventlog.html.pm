#lang pollen

◊(define-meta title "ckBTC internals: event log")
◊(define-meta keywords "ic,canisters")
◊(define-meta summary "Like event sourcing, but in a canister.")
◊(define-meta doc-publish-date "2023-04-21")
◊(define-meta doc-updated-date "2023-04-21")

◊section{
◊section-title["intro"]{Introduction}
◊p{
  The ◊a[#:href "https://medium.com/dfinity/chain-key-bitcoin-a-decentralized-bitcoin-twin-ceb8f4ddf95e"]{chain-key Bitcoin} (ckBTC) project became ◊a[#:href "https://twitter.com/dfinity/status/1642887821731004418"]{publicly available} on April 3, 2023.
  The ckBTC ◊em{minter} smart contract is the most novel part of the product responsible for converting Bitcoin to ckBTC and back.
  This system features a number of interesting design choices that some canister developers might find insightful.
  This article describes how the ckBTC minter, to which I will further refer as ◊quoted{the minter}, organizes its stable storage.
}
}

◊section{
◊section-title["motivation"]{Motivation}
◊p{
  The minter is a complicated system that must keep track of many data:
}
◊ul[#:class "arrows"]{
  ◊li{
    ◊a[#:href "https://en.wikipedia.org/wiki/Unspent_transaction_output"]{Unspent Transaction Outputs} (◊smallcaps{utxo}s) on the Bitcoin network the minter owns, indexed and sliced in various ways (by account, by state, etc.).
  }
  ◊li{
    ckBTC withdrawal requests, indexed by state and the arrival time.
  }
  ◊li{
    Pending Bitcoin transactions the minter has initiated to fulfill the withdrawal requests.
  }
  ◊li{
    Fees owed to the ◊a[#:href "https://thepaypers.com/expert-opinion/know-your-transaction-kyt-the-key-to-combating-transaction-laundering--1246231"]{Know Your Transaction} (KYT) service providers.
  }
}

◊p{
  How to preserve the data across canister upgrades?
}

◊p{
  On one hand, we didn't want to ◊a[#:href "/posts/11-ii-stable-memory.html#conventional-memory-management"]{marshal the entire state} through stable memory on each upgrade.
  We wanted to avoid pre-upgrade hooks altogether to eliminate the possibility that the minter becomes ◊a[#:href "/posts/01-effective-rust-canisters.html#upgrade-hook-panics"]{unupgradable} due to a bug in the hook.
}

◊p{
  On the other hand, we didn't want to invest to much time into crafting an efficient data layout using the ◊code-ref["/posts/14-stable-structures.html"]{stable-structures} package.
  All our data structures were in flux; we didn't want to commit to a specific representation too early.
}

◊p{
  Luckily, our problem has peculiarities we could exploit.
  All minter's state modifications are expensive: adding new ◊smallcaps{utxo}s requires the caller to invest at least a few dollars into a transaction on the Bitcoin network.
  Withdrawal requests involve paying transaction fees.
  In addition, the volume of modifications is relatively low because of the limitations of the Bitcoin network.
}
}

◊section{
◊section-title["solution"]{Solution}

◊p{
  The minter employs the ◊a[#:href "https://learn.microsoft.com/en-us/azure/architecture/patterns/event-sourcing"]{event sourcing} pattern to organize its stable storage.
  It declares a single stable data structure: the log of all events affecting the canister state.
}

◊p{
  Each time the minter modifies its state, it appends an event to the log.
  The event carries enough context to allow us to reproduce the state modification later.
}

◊p{
  On upgrade, the minter starts from an empty state and replays events from the log.
  This approach might sound inefficient, but it works great in our case:
}

◊ul[#:class "arrows"]{
  ◊li{
    The number of events is relatively low because most events involve a transfer on the Bitcoin network.
  }
  ◊li{
    The cost of replaying an event is low.
    Replaying twenty five thousands of events consumes less than one billion instructions, which is cheaper than submitting a single Bitcoin transaction.
  }
  ◊li{
    We can pause and resume the replay process to spread the work across multiple executions if the number of events goes out of hand.
  }
}

◊p{
  Furthermore, the event sourcing approach offers additional benefits beyond the original motivation:
}

◊ul[#:class "arrows"]{
  ◊li{
    The event log provides an audit for all state modifications, making the system more transparent and easier to debug.
  }
  ◊li{
    The event log is easy to replicate to other canisters and even off-chain.
    It's a perfect incremental backup solution.
  }
}
}

◊section{
◊section-title["testing"]{Testing}

◊p{
  One aspect of the event log design that I found challenging is ensuring that the events capture all essential state transitions.
}
}
