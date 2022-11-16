#lang pollen

◊(define-meta title "IC internals: the ICP ledger")
◊(define-meta keywords "ic, ledger")
◊(define-meta summary "The treasury of the Internet Computer utility tokens.")
◊(define-meta doc-publish-date "2022-12-01")
◊(define-meta doc-updated-date "2022-12-01")

◊section{
◊section-title["introduction"]{Introduction}
◊p{
  The ICP ledger is one of the first smart contracts hosted on the ◊a[#:href "https://internetcomputer.org"]{Internet Computer} (IC).
  As of October 2022, the ICP ledger holds hundreds of millions of dollars worth of tokens and never had a significant outage.
  In this article, we shall examine some design choices powering this critical canister.
}
}

◊section{
◊section-title["background"]{Background}
◊p{
  Unlike BTC for Bitcoin and ETH for Ethereum, the ICP token is not the Internet Computer's native currency◊sidenote["sn-cycles"]{◊em{Cycles} is the native currency of the ICP protocol. You pay cycles for installing and running smart contracts. The network allows you to exchange ICP for cycles with the help of the Cycles Minting Canister (CMC).}.
  ICP is an ◊em{utility token}, its main purpose is participation in the network governance.
}
◊p{
  In the early prototypes of the Internet Computer, canisters could hold ICP directly and send them around freely without consulting any third party.
  This design did not work well for two reasons.
}
◊ol-circled{
  ◊li{
    We must have a full record of all ICP transactions for regulatory purposes.
    When strict Swiss tax authorities asks you how you got your tokens, you better have an answer for them.
  }
  ◊li{
    We want centralized exchanges, such as ◊a[#:href "https://www.coinbase.com/"]{Coinbase}, to trade ICP.
    The industry standard for integration with centralized exachanges is ◊a[#:href "https://rosetta-api.org/"]{rosetta-api}.
    Since most of the canister state is private, the original design did not allow us to implement a specification-compliant Rosetta node.
  }
}
◊p{
  These needs defined the ICP ledger canister duties: it is responsible for keeping track of token balances, recording the transaction history, and interfacing with a Rosetta node implementation.
}
}

◊section{
◊section-title["account-id"]{Account identifiers}
◊p{
  The ICP ledger identifies accounts using 32-byte blobs computed from the owner's ◊a[#:href "https://internetcomputer.org/docs/current/references/ic-interface-spec/#principal"]{principal} and the ◊a[#:href "/posts/09-fungible-tokens-101.html#subaccounts"]{subaccount}, which is an arbitrary 32-byte blob identifying accounts belonging to the same owner.
}
◊source-code["pseudocode"]{
account_identifier := CRC32(h) || h
    ◊em{where} h = SHA224("\x0Aaccount-id" || principal || subaccount)
}
◊p{
  This design decision has quite a few upsides:
}
◊ul[#:class "arrows"]{
  ◊li{
    Account identifiers occupy about 50% less memory than ◊code{(principal, subaccount)} tuples, enabling the ICP ledger to fit a larger account book into the same memory space.
  }
  ◊li{
    A uniform 32-byte account structure makes it easy to find a unique and compact textual representation for accounts.
  }
}
◊p{
  On the other hand, the concept of account identifiers adds a few problems:
}
◊ul[#:class "arrows"]{
  ◊li{
    Account identifiers is yet another concept that people need to understand.
    The ◊smallcaps{ic} is already heavy on new concepts and terminology, unnecessary complication does not help adoption.
    For example, a few confused developers tried to pass principal bytes as an account identifier.
  }
  ◊li{
    Account identifier is a one-way function and the principal and the subaccount.
    This property makes the ledger less transaprent and complicates error recovery.
    For example, if one of the clients uses custom subaccounts but at some point forgets what they were, this client loses tokens.
  }
  ◊li{
    Opaqueness of identifiers limits types of applications and payment flows developers can build on top of the ledger.
    For example, a canister cannot inspect ledger blocks and detect incoming transactions easily if the payer used custom subaccounts.
  }
}
}

◊section{
◊section-title["tx-dedup"]{Transaction deduplication}
◊p{
  The IC has a mechanism protecting against message replay attacks.
  Each ingress message has an explicit ◊a[#:href "https://internetcomputer.org/docs/current/references/ic-interface-spec/#authentication"]{expiry time}; the IC remembers the message until it expires.
  The allowed expiry window is only a few minutes for scalability reasons: the larger the expiry window, the more message the IC must remember.
}
}

◊section{
◊section-title["block-encoding"]{Block encoding}
◊p{
}
}

◊section{
◊section-title["certification"]{Certification scheme}
◊p{
  The ICP ledger uses the ◊a[#:href ""]{certified variables} feature of the Internet Computer.
}
}

◊section{
◊section-title["tx-sigs"]{Transaction signatures}
}

◊section{
◊section-title["references"]{References}
◊ul[#:class "arrows"]{
  ◊li{
    The ICP ledger ◊a[#:href "https://internetcomputer.org/docs/current/references/ledger"]{specification}.
  }
}
}
