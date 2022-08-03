#lang pollen

◊(define-meta title "Fungible tokens 101")
◊(define-meta keywords "ic, ledger, finance")
◊(define-meta summary "An introduction to fungible tokens and ledgers.")
◊(define-meta doc-publish-date "2022-08-05")
◊(define-meta doc-updated-date "2022-08-05")

◊section{
◊section-title["intro"]{Introduction}
◊p{
  I am currently involved in the effort to deliver the ◊a[#:href "https://github.com/dfinity/ICRC-1"]{ICRC-1} fungible token standard for the ◊a[#:href "https://internetcomputer.org"]{Internet Computer}.
  The two most heated discussions in the working group centered on using ◊a[#:href "#subaccounts"]{subaccounts} and the core payment flow for smart contracts (in particular, the ◊code{approve}/◊code{transferFrom} flow popularized by the ◊a[#:href "https://eips.ethereum.org/EIPS/eip-20"]{ERC-20} token standard).
  At first glance, these issues seemed unrelated, but surprising connections revealed themselves under closer scrutiny, begging for analysis and exploration.
}
◊p{
  This article is a gentle introduction to fungible tokens and ledgers.
  We shall frame the concept of the ledger and design choices in designing a practical accounting system, laying the ground for more subtle technical topics that will come in future articles.
}
}

◊section{
◊section-title["fungible-tokens"]{Fungible tokens}
◊epigraph{
◊blockquote{
  ◊p{
  Gold is gold everywhere, fungible and indifferent.
  But when a disk of gold is stamped by a coiner with certain pompous words and the picture of a King, it takes on added value ◊mdash{} seigneurage. It has that value only in that people believe that it does ◊mdash{} it is a shared phant'sy.
  }
  ◊footer{Neal Stephenson, The Confusion}
}
}
◊p{
  The concept of ◊a[#:href "https://www.investopedia.com/terms/f/fungibility.asp"]{fungible} tokens is ancient and intimately familiar to us, though we rarely use this learned term of ◊a[#:href "https://en.wiktionary.org/wiki/fungible"]{latin origin} in everyday life.
  Fungible tokens are interchangeable items you can trade, such as coins of equal value or gold pieces of identical form, weight, and purity.
}
◊p{
  When you bought ice cream as a kid, you traded one fungible token (◊a[#:href "https://www.investopedia.com/terms/f/fiatmoney.asp"]{fiat money}) for another (ice cream).
  The salesperson at the store ◊a[#:href "https://en.wikipedia.org/wiki/Pecunia_non_olet"]{did not care} where your coins came from.
  Maybe your aunt gave you some to buy a treat, or perhaps you saved some from your lunch money.
  You did not care which instance of the desired sort of ice cream◊sidenote["plombieres"]{My absolute favorite is ◊a[#:href "https://en.wikipedia.org/wiki/Plombi%C3%A8res-les-Bains#Plombir_ice_cream"]{Plombières}.} you would get.
}
}

◊section{
◊subsection-title["asset-ledgers"]{Asset ledgers}
◊p{
  The most prominent examples of fungible tokens in the digital world are digital assets such as ◊a[#:href "https://bitcoin.org/"]{Bitcoin}, ◊a[#:href "https://ethereum.org/en/eth/"]{Ether}, and ◊a[#:href "https://wiki.internetcomputer.org/wiki/ICP_token"]{ICP} utility tokens.
  An ◊a[#:href "https://www.investopedia.com/terms/a/asset-ledger.asp"]{asset ledger} is a concept lying at the heart of these systems.
  Ledgers are journals of transactions the system executed; they keep track of fund movements between accounts.
  Each purchase you make with bitcoin becomes a record in the Bitcoin ledger packed into a block in the blockchain.
}
◊p{
  My ex-colleagues from ◊a[#:href "https://ya.ru"]{Yandex} used to use a simple ledger to keep track of tip money.
  I will use and evolve their scheme to demonstrate the concept of a ledger and its variations.
}
◊p{
  Geneviève goes into a small restaurant with two of her colleagues, Allen and Meriam.
  They get a fantastic meal and decide to tip ◊math{$20}.
  Allen and Meriam do not have ◊math{$6.66} to share the burden equally, so they ◊quoted{transfer} Geneviève imaginary money in a notebook with the word ◊quoted{LEDGER} on the cover.
  Each page in the notebook is a table with three columns.
}
◊table[#:class "table-3"]{
◊thead{
  ◊tr{◊td{From} ◊td{To} ◊td-num{Amount}}
}
◊tbody{
  ◊tr{◊td{Allen Brook} ◊td{Geneviève Bardot} ◊num-cell{$6.66}}
  ◊tr{◊td{Meriam Bone} ◊td{Geneviève Bardot} ◊num-cell{$6.66}}
}
}
◊p{
  Now Allen and Meriam have ◊math{-$6.66} on their ◊quoted{accounts}, and Geneviève has ◊math{$13.32}.
  The next day, they go to a fancy coffee shop and tip ◊math{$15}.
  This time Allen pays for everyone, and Geneviève and Meriam add new entries to the ledger.
}
◊table{
◊thead{
  ◊tr{◊td{From} ◊td{To} ◊td-num{Amount}}
}
◊tbody[#:class "table-3"]{
  ◊tr{◊td{Allen Brook} ◊td{Geneviève Bardot} ◊num-cell{$6.66}}
  ◊tr{◊td{Meriam Bone} ◊td{Geneviève Bardot} ◊num-cell{$6.66}}
  ◊tr{◊td{Geneviève Bardot} ◊td{Allen Brook} ◊num-cell{$5.00}}
  ◊tr{◊td{Meriam Bone} ◊td{Allen Brook} ◊num-cell{$5.00}}
}
}
◊p{
  Now Allen has ◊math{$3.34} on his account, Geneviève has ◊math{$8.32}, and Meriam has ◊math{-$11.66}◊sidenote["sn-compute-balance"]{
    To compute a person's balance, go over all the records in the log from top to bottom.
    If the person appears in the ◊em{from} column, subtract the ◊em{amount} from their balance;
    if the person appears in the ◊em{to} column, add the ◊em{amount} to their balance.
  }.
  This ledger has an interesting property: the sum of all balances is always zero because we started with no funds, and each record only moves funds.
}
◊p{
  The tip ledger is unusual because it allows negative balances like credit cards.
  This setup works well when all the participants know and trust each other.
  Digital ledgers such as Bitcoin are much stricter: you must have enough tokens on your account before making a transfer.
  But how do the first tokens get into the system?
}

◊subsection-title["minting-burning"]{Minting and burning}
◊p{
  All ledgers have a way to produce, or ◊em{mint}◊sidenote["sn-newton-ming"]{Did you know that Sir Isaac Newton worked at the ◊a[#:href "https://newtonandthemint.history.ox.ac.uk/"]{Royal Mint} for three decades?}, tokens out of thin air.
  Bitcoin network mints tokens as a reward for participants that help the ledger grow.
  The IC mints ICP utility tokens to reward participants in the network governance and node providers.
  Another popular scheme is ◊em{wrapped tokens}, where the ledger mints tokens as proxies for other assets.
}
◊p{
  Let us get back to our tip ledger example.
  Imagine now that Geneviève does not trust the folks she hangs out with, but she wants to use the convenience of virtual money.
  Whenever someone transfers her virtual tokens on a piece of paper, she wants to be sure she can claim her buck back.
}
◊p{
  One way to approach the issue is to set up a piggy bank at the office.
  Anyone who puts ◊math{$1} into the bank gets a virtual ◊math{$1} on the ledger.
  The transaction that converts a physical bill into a virtual token is a ◊em{mint} transaction.
}
◊p{
  One day Geneviève, Allen, and Meriam put ◊math{$10} each into the piggy and get their virtual tip money minted on the ledger.
}
◊table[#:class "table-4"]{
◊thead{
  ◊tr{◊td{From} ◊td{To} ◊td-num{Amount} ◊td-num{Piggy bank}}
}
◊tbody{
  ◊tr{◊td{◊mdash{}} ◊td{Geneviève Bardot} ◊num-cell{$10.00} ◊num-cell{$10.00}}
  ◊tr{◊td{◊mdash{}} ◊td{Allen Brook} ◊num-cell{$10.00} ◊num-cell{$20.00}}
  ◊tr{◊td{◊mdash{}} ◊td{Meriam Bone} ◊num-cell{$10.00} ◊num-cell{$30.00}}
}
}
◊p{
  Then they all go to a coffee shop where Geneviève tips ◊math{$6} for the group.
  Allen and Meriam transfer their shares to Geneviève virtually. 
}
◊table[#:class "table-4"]{
◊thead{
  ◊tr{◊td{From} ◊td{To} ◊td-num{Amount} ◊td-num{Piggy bank}}
}
◊tbody{
  ◊tr{◊td{◊mdash{}} ◊td{Geneviève Bardot} ◊num-cell{$10.00} ◊num-cell{$10.00}}
  ◊tr{◊td{◊mdash{}} ◊td{Allen Brook} ◊num-cell{$10.00} ◊num-cell{$20.00}}
  ◊tr{◊td{◊mdash{}} ◊td{Meriam Bone} ◊num-cell{$10.00} ◊num-cell{$30.00}}
  ◊tr{◊td{Allen Brook} ◊td{Geneviève Bardot} ◊num-cell{$◊numsp{}2.00} ◊num-cell{$30.00}}
  ◊tr{◊td{Meriam Bone} ◊td{Geneviève Bardot} ◊num-cell{$◊numsp{}2.00} ◊num-cell{$30.00}}
}
}
◊p{
  The main difference with the original scheme is that now Geneviève can exit the group and get her money back at any point.
  All she needs is to open the piggy under a supervision of a trusted party, get her ◊math{$14} and record a ◊em{burn} transaction on the ledger by sending her tokens to the void.
  The sum of all balances on the ledger must be equal to the amount of money in the piggy bank.
}
◊table[#:class "table-4"]{
◊thead{
  ◊tr{◊td{From} ◊td{To} ◊td-num{Amount} ◊td-num{Piggy bank}}
}
◊tbody{
  ◊tr{◊td{◊mdash{}} ◊td{Geneviève Bardot} ◊num-cell{$10.00} ◊num-cell{$10.00}}
  ◊tr{◊td{◊mdash{}} ◊td{Allen Brook} ◊num-cell{$10.00} ◊num-cell{$20.00}}
  ◊tr{◊td{◊mdash{}} ◊td{Meriam Bone} ◊num-cell{$10.00} ◊num-cell{$30.00}}
  ◊tr{◊td{Allen Brook} ◊td{Geneviève Bardot} ◊num-cell{$◊numsp{}2.00} ◊num-cell{$30.00}}
  ◊tr{◊td{Meriam Bone} ◊td{Geneviève Bardot} ◊num-cell{$◊numsp{}2.00} ◊num-cell{$30.00}}
  ◊tr{◊td{Geneviève Bardot} ◊td{◊mdash{}} ◊num-cell{$14.00} ◊num-cell{$16.00}}
}
}
◊p{
  Wrapped tokens are not a recent invention: the U.S. dollar ◊a[#:href "https://en.wikipedia.org/wiki/Gold_standard"]{was} a wrapped token for 1.50463 grams of gold in ◊a[#:href "https://en.wikipedia.org/wiki/Coinage_Act_of_1873"]{1873}.
}

◊subsection-title["subaccounts"]{Subaccounts}
◊p{
  Geneviève and her colleagues have a tradition: when someone has a birthday, other colleagues raise funds to buy a little present.
  Next week Allen turns thirty-three, so the department tasked Geneviève to buy something nice for him.
  This time they decided to use the piggy bank ledger discussed in the previous section to transfer funds for the present.
  However, there is one little issue: if everyone transfers gift money to Geneviève directly, how will she separate her money from the gift money?
}
◊p{
  Our clever office folks decided to add a new feature to the ledger to address the fund separation problem.
  Everyone can hold multiple disjoint accounts on the ledger and move funds from any of those accounts.
  A ◊a[#:href "https://www.investopedia.com/terms/s/sub-account.asp"]{subaccount} will be a label demarcating independent accounts belonging to the same person.
}
◊p{
  Geneviève asks colleagues to transfer funds to her ◊code{NYYRA OVEGUQNL}◊sidenote["nm-subaccount-crypto"]{Geneviève applied advanced cryptography to hide the purpose of the subaccount from Allen.} subaccount until the end of the day.
  She burns the tokens on her ◊code{NYYRA OVEGUQNL} subaccount and withdraws ◊math{$42.00} from the piggy bank right before leaving the office.
}
◊table[#:class "table-5"]{
◊thead{
  ◊tr{◊td{From} ◊td{Subaccount} ◊td{To} ◊td{Subaccount} ◊td-num{Amount}}
}
◊tbody{
  ◊tr{◊td[#:colspan "5"]{◊center{◊mid-ellipsis{}}}}
  ◊tr{◊td{Geneviève Bardot} ◊td{◊mdash{}} ◊td{Geneviève Bardot} ◊td{NYYRA OVEGUQNL} ◊num-cell{$15.00}}
  ◊tr{◊td{Meriam Bone} ◊td{◊mdash{}} ◊td{Geneviève Bardot} ◊td{NYYRA OVEGUQNL} ◊num-cell{$15.00}}
  ◊tr{◊td{Rüdiger Bachmann} ◊td{◊mdash{}} ◊td{Geneviève Bardot} ◊td{NYYRA OVEGUQNL} ◊num-cell{$12.00}}
  ◊tr{◊td{Geneviève Bardot} ◊td{NYYRA OVEGUQNL} ◊td{◊mdash{}} ◊td{◊mdash{}} ◊num-cell{$42.00}}
}
}
◊p{
  Geneviève heads to the book store and buys the latest edition of ◊a[#:href "https://www.amazon.com/-/en/dp/0884271951"]{The Goal} by Eliyahu M. Goldratt.
  What a great birthday present!
}
◊p{
  Overall, subaccounts are a helpful feature allowing you not to put all your tokens in a single basket.
  Your bank likely opened more than one account for you, such as a salary and a savings account.
}
◊subsection-title["approvals"]{Approvals}
◊p{
  One day Geneviève's nephew, Alex, comes to visit her at work.
  Geneviève has an important call with a customer and could not take Alex out for lunch.
  Her colleagues were happy to go out with Alex, but there was a little problem: Alex did not have money.
}
◊p{
  Luckily, Geneviève accumulated quite some balance on the ledger, so someone could pay for Alex and get her ledger money back in exchange.
  All that was left is to formalize this arrangement on the ledger.
}
◊p{
  Geneviève could transfer some budget to Alex before he goes out, and he could transfer her the leftover when he is back.
  That solves the problem, but Geneviève cannot use the locked funds herself during that time.
}
◊p{
  Another approach popularized by the Etherium community is to introduce the notion of ◊em{approvals}.
  The ledger could have another table with spending allowances between two people.
}
◊table[#:class "table-3"]{
◊thead{
  ◊tr{◊td{From} ◊td{To} ◊td-num{Allowance}}
}
◊tbody{
  ◊tr{◊td{Geneviève Bardot} ◊td{Alex Schiller} ◊num-cell{$25.00}}
}
}
◊p{
  With this record, Alex can transfer money on behalf of Geneviève up to the allowance.
}
◊p{
  Alex had a lot of fun with Geneviève's colleagues and spent ◊math{$16.00} at a coffee shop.
  Allen paid for Alex, and Alex transferred some of Geneviève's tokens to Allen in return.
  This arrangement resulted in two updates to the ledger.
  The first update is the new transaction in the log.
  Note that we need a new column in the table, ◊smallcaps{on behalf of}, to indicate that Alex initiated the transaction, but Geneviève is the effective payer.
}
◊table[#:class "table-4"]{
◊thead{
  ◊tr{◊td{From} ◊td{On behalf of} ◊td{To} ◊td-num{Amount}}
}
◊tbody{
  ◊tr{◊td[#:colspan "4"]{◊center{◊mid-ellipsis{}}}}
  ◊tr{◊td{Alex Schiller} ◊td{Geneviève Bardot} ◊td{Allen Brook} ◊num-cell{$16.00}}
}
}
◊p{
  The second update lowers the allowance in the approval table by the amount Alex spent.
}
◊table[#:class "table-3"]{
◊thead{
  ◊tr{◊td{From} ◊td{To} ◊td-num{Allowance}}
}
◊tbody{
  ◊tr[#:class "strikethrough"]{◊td{Geneviève Bardot} ◊td{Alex Schiller} ◊num-cell{$25.00}}
  ◊tr{◊td{Geneviève Bardot} ◊td{Alex Schiller} ◊num-cell{$◊numsp{}9.00}}
}
}

◊subsection-title["fees"]{Fees}
◊p{
  Peppy was a lovely five-year-old girl who came to the office space to see how her mother, Meriam, spends her days.
  Peppy loved numbers, could write her name, and were unusually rational for her age.
  Her favorite game was finding holes in ad-hoc rules that grown-ups invent all day.
  Her eyes caught a little devilish fire when she saw how her mother used the legder notebook.
}
◊p{
  ◊quoted{How much can I send you, Mom?} asked Peppy.
}
◊p{
  ◊quoted{No more than you have on your account,} replied Meriam.
}
◊p{
  ◊quoted{I don't have anything yet. Can I send ◊em{nothing}?}
}
◊p{
  ◊quoted{Ahm◊ellipsis{} Well, there are no rules prohibiting ◊em{that}, I suppose.}
}
◊p{
  Peppy grabbed a pen and started filling the lines with blocky letters.
}
◊table[#:class "table-3"]{
◊thead{
  ◊tr{◊td{From} ◊td{To} ◊td-num{Amount}}
}
◊tbody{
  ◊tr{◊td[#:colspan "3"]{◊center{◊mid-ellipsis{}}}}
  ◊tr{◊td[#:class "fun"]{PEPPY} ◊td[#:class "fun"]{MOM} ◊td-num{◊span[#:class "fun"]{$0}}}
  ◊tr{◊td[#:class "fun"]{PEPPY} ◊td[#:class "fun"]{MR ALLEN} ◊td-num{◊span[#:class "fun"]{$0}}}
  ◊tr{◊td[#:class "fun"]{PEPPY} ◊td[#:class "fun"]{MOM} ◊td-num{◊span[#:class "fun"]{$0}}}
}
}
◊p{
  ◊quoted{OK, Peppy, stop. There is a new rule: you cannot transfer ◊em{nothing}. Only a positive amount.}
}
◊p{
  Peppy stopped.
  A few wrinkles appeared on her forehead, and then her lips curled into a smile.
  She opened her little backpack with tiger stripes and fetched a nickel she found on the street a few days ago.
  She put the nickel into the piggy bank and recorded a mint.
  She did not stop there, however.
}
◊table[#:class "table-3"]{
◊thead{
  ◊tr{◊td{From} ◊td{To} ◊td-num{Amount}}
}
◊tbody{
  ◊tr{◊td[#:colspan "3"]{◊center{◊mid-ellipsis{}}}}
  ◊tr{◊td[#:class "fun"]{◊mdash{}} ◊td[#:class "fun"]{PEPPY} ◊td-num{◊span[#:class "fun"]{$0.05}}}
  ◊tr{◊td[#:class "fun"]{PEPPY} ◊td[#:class "fun"]{PEPPY} ◊td-num{◊span[#:class "fun"]{$0.05}}}
  ◊tr{◊td[#:class "fun"]{PEPPY} ◊td[#:class "fun"]{PEPPY} ◊td-num{◊span[#:class "fun"]{$0.05}}}
}
}
◊p{
  ◊quoted{OK, Peppy, a new rule: you can't transfer to yourself. There is no reason to do that!}
}
◊p{
  Peppy knit her brows, struggling to come up with a counter-action.
  Ten seconds later, she was scribbling again.
  She was so focused that the tip of her tongue stuck from her mouth.
}
◊table[#:class "table-3"]{
◊thead{
  ◊tr{◊td{From} ◊td{To} ◊td-num{Amount}}
}
◊tbody{
  ◊tr{◊td[#:colspan "3"]{◊center{◊mid-ellipsis{}}}}
  ◊tr{◊td[#:class "fun"]{PEPPY} ◊td[#:class "fun"]{MOM} ◊td-num{◊span[#:class "fun"]{$0.0001}}}
  ◊tr{◊td[#:class "fun"]{PEPPY} ◊td[#:class "fun"]{MR ALLEN} ◊td-num{◊span[#:class "fun"]{$0.0001}}}
}
}
◊p{
  ◊quoted{It's not funny, Peppy. From now on, every record will cost the sender a penny.}
}
◊p{
  Peppy pursed her lips, wrote four more records to the notebook, and visited Mrs. Geneviève, who had a chocolate bar in her upper drawer.
}
◊p{
  Fees are an essential instrument in ledger design.
  The bitcoin network uses fees to protect the system against spam transactions and incentivize the nodes to include transactions into blocks.
  The higher the fee the transaction sender is willing to pay, the more likely the nodes to process the transaction.
  The ICP ledger also uses fees as a mechanism for spam prevention.
}
}

◊section{
◊section-title["summary"]{Summary}
◊p{
  We have seen that fungible tokens are an essential part of our daily life.
  We learned that ◊a[#:href "#asset-ledgers"]{ledger} is a robust accounting mechanism that we can adapt to the task at hand with various features: ◊a[#:href "#minting-burning"]{mints}, ◊a[#:href "#subaccounts"]{subaccounts}, ◊a[#:href "#approvals"]{approvals}, and ◊a[#:href "#fees"]{transfer fees}.
  In the following article, we will discuss protocols allowing clients to exchange tokens for service, known as ◊em{payment flows}.
}
}