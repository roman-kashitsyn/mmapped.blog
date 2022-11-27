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
    Since there Internet Computer blocks distributed across multiple ◊a[#:href "/posts/08-ic-xnet.html#subnets"]{subnets} and hard to access, detailed ICP accounting would be virtually impossible.
  }
  ◊li{
    We want centralized exchanges, such as ◊a[#:href "https://www.coinbase.com/"]{Coinbase}, to trade ICP.
    The industry standard for integration with centralized exachanges is the ◊a[#:href "https://rosetta-api.org/"]{Rosetta API}.
    Since most of the network state is inaccessible to general public, the original design did not allow us to implement a specification-compliant Rosetta node.
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
◊figure{
◊marginnote["mn-account-id"]{
  The pseudocode for computing an account identifier for a given ◊a[#:href "https://internetcomputer.org/docs/current/references/ic-interface-spec#principal"]{principal} and a subaccount (an arbitrary 32-byte array).
  The computation uses the ◊a[#:href "https://crypto.stackexchange.com/questions/43430/what-is-the-reason-to-separate-domains-in-the-internal-hash-algorithm-of-a-merkl"]{domain separation} technique.
  The ◊code{0x0A} byte in the domain separator indicates the length of the ◊quoted{account-id} string.
}
◊source-code["pseudocode"]{
account_identifier(principal, subaccount) := CRC32(h) || h
    ◊em{where} h = SHA224("\x0Aaccount-id" || principal || subaccount)
}
}
◊p{
  This design decision offers several benefits:
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
◊section-title["blocks-and-transactions"]{Blocks and transactions}
◊p{
  The ◊a[#:href "https://rosetta-api.org"]{Rosetta API} expects a blockchain to have ◊em{blocks} containing ◊em{transactions}.
  Smart contracts on the IC do not have access to raw blocks and messages within them, so the ICP ledger models its own ◊quoted{blockchain} to satisfy the Rosetta data model. 
  Each ledger operation, such as minting or transferring tokens, becomes a transaction that the ledger wraps into a unique block and adds to the chain.
}

◊p{
  The ICP ledger uses ◊a[#:href "https://developers.google.com/protocol-buffers"]{Protocol Buffers} to encode transactions and blocks.
  This encoding offers a few benefits:
}
◊ul[#:class "arrows"]{
  ◊li{
    Protocol Buffers offer solid tooling (including a ◊a[#:href "https://docs.buf.build/breaking/overview"]{breaking change detector}) that allowed the team to launch the ledger quicker.
  }
  ◊li{
    The ◊a[#:href "https://developers.google.com/protocol-buffers/docs/encoding"]{encoding} is simple and easy to implement in a memory-constrained device, such as a ◊a[#:href "https://www.ledger.com/"]{Ledger} hardware wallet.
  }
  ◊li{
    The encoding is compact and efficient, comparable to the custom ◊a[#:href "https://developer.bitcoin.org/reference/transactions.html#raw-transaction-format"]{Bitcoin serialization format}.
  }
}
◊p{
  The main disadvantage of the Protocol Buffers encoding is its ◊a[#:href "https://developers.google.com/protocol-buffers/docs/encoding#implications"]{non-determinism}.
  If you start from a block, decode it into a data structure, and encode it back accoriding to the ◊a[#:href "https://github.com/dfinity/ic/blob/5248f11c18ca564881bbb82a4eb6915efb7ca62f/rs/rosetta-api/icp_ledger/proto/ic_ledger/pb/v1/types.proto"]{Protocol Buffer scheme}, you might end up with bytes that differ from the original.
}
◊p{
  The ICP ledger uses a deterministic Protocol Buffer encoder to mitigate the non-determinism issue.
  The ICP ledger specification describes the ◊a[#:href "https://internetcomputer.org/docs/current/references/ledger/#_chaining_ledger_blocks"]{exact encoding} that implementations should use.
}
}


◊section{
◊section-title["tx-dedup"]{Transaction deduplication}
◊p{
  The IC has a mechanism protecting against message replay attacks.
  Each ingress message has an explicit ◊a[#:href "https://internetcomputer.org/docs/current/references/ic-interface-spec/#authentication"]{expiry time}; the IC remembers the message until it expires.
  The allowed expiry window is only a few minutes for scalability reasons: the larger the expiry window, the more message the IC must remember.
}
◊p{
  Centralized exchanges such as Coinbase often offer ◊a[#:href "https://www.coindesk.com/learn/what-is-crypto-custody/"]{custody services}: they hold the private key controlling your tokens in a safe place for a fee.
}
}
◊section{
◊section-title["certification"]{Certification scheme}
◊p{
  The ICP ledger uses the ◊a[#:href ""]{certified variables} feature of the Internet Computer.
}
}

◊section{
◊section-title["block-archives"]{Block archives}
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
