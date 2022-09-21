#lang pollen

◊(require txexpr)
◊(define-meta title "Fungible tokens: payment flows")
◊(define-meta keywords "ic, ledger, finance")
◊(define-meta summary "Payment flows for fungible tokens.")
◊(define-meta doc-publish-date "2022-09-21")
◊(define-meta doc-updated-date "2022-09-21")

◊(define (img-icon name) (txexpr 'img `((class "grayscale") (src ,(string-append "/images/10-" name ".png")) (alt ,name) (height "50px") (width "50px") (style "vertical-align: middle;")) empty))

◊section{
◊section-title["introduction"]{Introduction}
◊p{
  In the previous article, ◊a[#:href "/posts/09-fungible-tokens-101.html"]{Fungible tokens 101}, I introduced the concept of a ledger and various extensions that can help us solve practical problems.
  In this article, we shall analyze a few ◊em{payment flows}◊mdash{}protocols built on top of a ledger allowing clients to exchange tokens for a service◊mdash{}in the context of the ◊a[#:href "https://internetcomputer.org"]{Internet Computer}.
}
}

◊section{
◊section-title["prerequisites"]{Prerequisites}
◊subsection-title["the-payment-scenario"]{The payment scenario}
◊p{
  Abstract protocols can be dull and hard to comprehend, so let us model a specific payment scenario: me buying a new laptop online and paying for it in ◊smallcaps{wxdr} (wrapped ◊a[#:href "https://en.wikipedia.org/wiki/Special_drawing_rights"]{SDR}) tokens locked in a ledger hosted on the Internet Computer.
}
◊p{
  I open the website of the hardware vendor I trust, select the configuration (the memory capacity, the number of cores, etc.) that suits my needs, fill in the shipment details, and go to the payment page.
  I choose an option to pay in ◊smallcaps{wxdr}.
}
◊p{
  In the rest of the article, we will fantasize about what the payment page can look like and how it can interact with the shop.
}

◊subsection-title["participants"]{Participants}
◊p{
  Each flow will involve the following participants:
}
◊table{
◊tbody{
◊tr{
  ◊td[#:style "border-top: 0px; min-width:50px; min-height:50px;"]{◊img-icon{me}}
  ◊td[#:style "border-top: 0px;"]{◊em{Me}: a merry human sitting in front of a computer and ordering a new laptop.}
}
◊tr{
  ◊td{◊img-icon{shop}}
  ◊td{◊em{Shop}: an Internet Computer smart contract accepting orders.}
}
◊tr{
  ◊td{◊img-icon{webpage}}
  ◊td{◊em{Web page}: a spaghetti of markup, styling, and scripts serving the ◊em{shop} UI.}
}
◊tr{
  ◊td{◊img-icon{wallet}}
  ◊td{◊em{Wallet}: a trusty hardware wallet device, such as ◊a[#:href "https://www.ledger.com/"]{Ledger} or ◊a[#:href "https://trezor.io/"]{Trezor}, with a corresponding UI for interacting with the ledger, such as ◊a[#:href "https://www.ledger.com/ledger-live"]{Ledger Live}. A more sophisticated wallet can smoothen the UX, but the ideas remain the same.
}
}
◊tr{
  ◊td{◊img-icon{ledger}}
  ◊td{◊em{Ledger}: an Internet Computer smart contract processing payments.}
}
}
}

◊subsection-title["payment-phases"]{Payment phases}
◊p{
  All the payment flows we will analyze have three phases:
}
◊ol-circled{
  ◊li{
    ◊em{The negotiation phase}.
    After I place my order and fill in the shipment details, the shop creates a unique order identifier, ◊em{Invoice ID}.
    The ◊em{web page} displays the payment details (e.g., as a QR code of the request I need to sign) and instructions on how to proceed with the order.
  }
  ◊li{
    ◊em{The payment phase}.
    I use my ◊em{wallet} to execute the transaction as instructed on the ◊em{web page}.
    This phase is essentially the same in all flows; only the transaction type varies.
  }
  ◊li{
    ◊em{The notification phase}.
    The shop receives a payment notification for the Invoice ID, validates the payment, and updates the order status.
    The ◊em{web page} displays an upbeat message, completing the flow.
  }
}
}

◊section{
◊section-title["invoice-account"]{Invoice account}
◊p{
  The first payment flow we will analyze relies on the ◊a[#:href "/posts/09-fungible-tokens-101.html#subaccounts"]{subaccounts} ledger feature.
  The idea behind the flow is quite clever: the shop can use its subaccount identified by the ◊em{Invoice ID} as a temporary ◊quoted{cell} for the payment.
  I can transfer my tokens to this cell, and the shop can move tokens out because the cell belongs to the shop.
}
◊p{
  The happy case of the flow needs only one primitive from the ledger, the ◊code{transfer} method specified below.
}
◊source-code["candid"]{
service : {
  ◊em{// Transfers token ◊b{amount} from the account of the (implicit) ◊b{caller}}
  ◊em{// to the account specified by the principal and the subaccount.}
  ◊em{// Arguments:}
  ◊em{//   ◊b{amount} - the token amount to transfer.}
  ◊em{//   ◊b{from_subaccount} - the subaccount of the caller to transfer tokens from.}
  ◊em{//   ◊b{to} - the receiver of the tokens.}
  ◊em{//   ◊b{to_subaccount} - which subaccount of the receiver the tokens will land on.}
  ◊b{transfer}(record {
    amount : nat;
    from_subaccount : opt blob;
    to : principal;
    to_subaccount : opt blob;
  }) -> (TxReceipt);
}
}

◊p{
  The flow proceeds as follows:
}
◊ol-circled{
  ◊li{
    In the negotiation phase, the webpage instructs me to transfer tokens to the shop's ◊em{Invoice ID} subaccount and displays a big green ◊quoted{Done} button that I need to press after the payment succeeds.
  }
  ◊li{
    In the payment phase, I use my wallet to execute the ◊code{transfer({ amount = Price, to = Shop, to_subaccount = InvoiceId})} call on the ledger.
  }
  ◊li{
    In the notification phase, I click on the ◊quoted{Done} button dispatching a notification to the ◊em{shop} indicating that I paid the invoice (the webpage can remember the ◊em{Invoice ID} on the client side, so I do not have to type it in).
    Upon receiving the notification, the shop attempts to transfer the amount from its ◊em{Invoice ID} subaccount to its default account, calling ◊code{transfer({ amount = Price - Fee, from_subaccount = InvoiceID, to = Shop })} on the ledger.
    If that final transfer succeeds, the order is complete.
  }
}

◊figure[#:class "grayscale-diagram"]{
◊marginnote["mn-invoice-account-seq"]{
  A sequence diagram for the invoice account payment flow.
}
◊p{◊img[#:src "/images/10-invoice-id-flow.png"]{}}
}

◊p{
  The invoice account flow has a few interesting properties:
}

◊ul[#:class "arrows"]{
  ◊li{The ledger must process at least two messages: one transfer from me and another from the shop.}
  ◊li{Two transfers mean that the ledger charges ◊em{two} fees for each flow: one from me and another from the shop.}
  ◊li{
    The ledger needs to remember one additional ◊code{(principal, subaccount, amount)} tuple for the duration of the flow.
    The tuple occupies at least 70 bytes.
  }
  ◊li{The flow supports unlimited concurrency: I can make multiple payments to the same shop in parallel as long as each payment uses a unique invoice identifier.}
  ◊li{
    The ledger implementation is straightforward: the subaccounts feature is the only requirement for the flow.
  }
}

◊p{
  What happens if I transfer my ◊smallcaps{wxdr}s but never click the ◊quoted{Done} button?
  Or what if my browser loses network connection right before it sends the shop notification?
  The shop will not receive any notifications, likely never making progress with my order.
  One strategy that the shop could use to improve the user experience in such cases is to monitor balances for unpaid invoices and complete transactions automatically if the notification does not arrive in a reasonable amount of time.
}
}

◊section{
◊section-title["approve-transfer-from"]{Approve-transfer-from}

◊p{
  The approve-transfer-from pattern relies on the ◊a[#:href "/posts/09-fungible-tokens-101.html#approvals"]{approvals} ledger feature, first appearing in the ◊a[#:href "https://ethereum.org/en/developers/docs/standards/tokens/erc-20/"]{ERC-20} token standard.
  The flow uses two new ledger primitives, ◊code{approve} and ◊code{transfer_from}, and involves three parties:
}
◊ol-circled{
  ◊li{The ◊em{owner} holds tokens on the ledger. The owner can ◊em{approve} transfers from its account to a ◊em{delegate}.}
  ◊li{The ◊em{delegate} can ◊em{transfer} tokens ◊em{from} the owner's account within the approved cap.}
  ◊li{The ◊em{beneficiary} receives tokens from the delegate as if the owner sent them.}
}
◊p{
  In our ◊a[#:href "#payment-scenario"]{scenario}, the delegate and the beneficiary are the same entity ◊mdash{} the ◊em{shop}.
}
◊p{
  We can capture the required ledger primitives in the following Candid interface:
}

◊source-code["candid"]{
service : {
  ◊em{// Entitles the ◊b{delegate} to spend at most the specified token ◊b{amount} on behalf}
  ◊em{// of the (implicit) ◊b{caller}.}
  ◊em{// Arguments:}
  ◊em{//   ◊b{amount} - the cap on the amount the delegate can transfer from the caller's account.}
  ◊em{//   ◊b{delegate} - the actor entitled to make payments on behalf of the caller.}
  ◊b{approve}(record {
    amount : nat;
    delegate : principal;
  }) -> ();

  ◊em{// Transfers the specified token ◊b{amount} from the ◊b{owner} account to the}
  ◊em{// specified account.}
  ◊em{// Arguments:}
  ◊em{//   ◊b{amount} - the token amount to transfer.}
  ◊em{//   ◊b{owner} - the account to transfer tokens from.}
  ◊em{//   ◊b{to} - the receiver of the tokens (the beneficiary).}
  ◊em{//}
  ◊em{// PRECONDITION: the ◊b{owner} has approved at least the ◊b{amount} to the (implicit) ◊b{caller}.}
  ◊em{// POSTCONDITION: the caller's allowance decreases by the ◊b{amount}.}
  ◊b{transfer_from}(record {
    amount : nat;
    owner : principal;
    to : principal;
  }) -> (nat) query;
}
}

◊p{
  The flow proceeds as follows:
}
◊ol-circled{
  ◊li{
    In the negotiation phase, the webpage instructs me to approve a transfer to the shop, displaying the shop's account.
    One difference from the ◊a[#:href "invoice-account"]{invoice account} flow is that the shop needs to know my wallet's address on the ledger to make a transfer on my behalf.
    The webpage displays a text field for my account and the familiar ◊quoted{Done} button.
  }
  ◊li{In the payment phase, I use my wallet to execute the ◊code{approve({to = Shop, amount = Price})} call on the ledger.}
  ◊li{
    In the notification phase, I paste my ledger address into the text field and press the button.
    Once the shop receives the notification with my address and the ◊em{Invoice ID}, it executes ◊code{transfer_from({ amount = Price; owner = Wallet; to = Shop })} call on the ledger.
    If that transfer is successful, the order is complete.
  }
}

◊figure[#:class "grayscale-diagram"]{
◊marginnote["mn-approve-transfer-from-seq"]{
  A sequence diagram for the approve-transfer-from payment flow.
}
◊p{◊img[#:src "/images/10-approve-flow.png"]{}}
}

◊p{
  Let us see how this flow compares to the ◊a[#:href "#invoice-account"]{invoice account} flow:
}

◊ul[#:class "arrows"]{
  ◊li{The ledger must process at least two messages: approval from the owner and a transfer from the shop.}
  ◊li{The ledger charges ◊em{two} fees for each payment: one for my approval and another for the shop's transfer.}
  ◊li{
    The ledger needs to remember one additional ◊code{(principal, principal, amount)} tuple for the duration of the flow.
    The tuple occupies at least 68 bytes.
  }
  ◊li{
    The flow does not support concurrency: if I execute two payments to the same shop asynchronously, only one of the payments will likely succeed (the exact outcome depends on the message scheduling order).
  }
  ◊li{
    The ledger needs to maintain a data structure to track allowances, adding complexity to the implementation.
  }
  ◊li{
    I still have the tokens on my account if the shop never gets the notification due to a bug or a networking issue.
  }
}
◊p{
  One strong side of the approve-transfer-from flow is that it supports recurring payments.
  For example, if I were buying a subscription with monthly installments, I could have approved transfers for the entire year, allowing the shop to transfer from my account once a month.
  Of course, I must trust the shop not to charge the whole yearly amount in one go.
}
}

◊section{
◊section-title["transfer-notify"]{Transfer-notify}
◊p{
  Note that the failure of the frontend to send a notification is a prevalent error in the previous flows.
  What if the ledger automatically delivered the notification to the receiver over the reliable channel that the Internet Computer provides?
  That is the idea behind the transfer-notify flow.
}
◊p{
  There is one issue we need to sort out, however.
  When we relied on the webpage to send the notification, we could include the ◊em{Invoice ID} into the payload, making it possible for the shop to identify the relevant order.
  If we ask the ledger to send the payment notification, we must pass the ◊em{Invoice ID} in that message.
  The common way to address this issue is to add the ◊code{memo} argument to the transfer arguments, allowing the caller to attach an arbitrary payload to the transaction details.
}

◊source-code["candid"]{
service : {
  ◊em{// Transfers token ◊b{amount} from the account of the (implicit) ◊b{caller}}
  ◊em{// to the account specified by the principal.}
  ◊em{// If the transfer is successful, sends a notification to the receiver.}
  ◊em{// Arguments:}
  ◊em{//   ◊b{amount} - the token amount to transfer.}
  ◊em{//   ◊b{to} - the receiver of the tokens.}
  ◊em{//   ◊b{memo} - an opaque identifier attached to the notification.}
  ◊b{transfer_notify}(record {
    amount : nat;
    to : principal;
    memo : opt blob;
  }) -> (TxReceipt);
}
}

◊p{
  The flow proceeds as follows:
}
◊ol-circled{
  ◊li{In the negotiation phase, the webpage displays the payment details and starts polling the shop for payment confirmation.}
  ◊li{In the payment phase, I use my wallet to execute the ◊code{transfer_notify({to = Shop, amount = Price, memo = InvoiceID})} call on the ledger.}
  ◊li{
    Once the transfer succeeds, the ledger notifies the shop about the payment, providing the amount and the ◊code{memo} containing the ◊em{Invoice ID}.
    The shop consumes the notification and changes the order status.
    The next time the webpage polls the shop, the shop replies with a confirmation, and I see a positive message.
  }
}

◊figure[#:class "grayscale-diagram"]{
◊marginnote["mn-transfer-notify-seq"]{
  A sequence diagram for the transfer-notify payment flow.
}
◊p{◊img[#:src "/images/10-notify-flow.png"]{}}
}
◊p{
  Let us check how this flow compares to the previous ones:
}
◊ul[#:class "arrows"]{
  ◊li{The ledger must process at least two messages: a transfer from the owner and a notification to the shop.}
  ◊li{
    The ledger charges a combined fee for my transfer and notification.
    Whether the ledger charges two fees or gives a discount depends on the implementation.
    Let us assume that the ledger charges 1½ fees.
  }
  ◊li{
    The ledger needs to hold a notification in memory until the flow completes.
    The notification must contain at least the payer principal, the memo (up to 32 bytes), and the amount, which amounts to at least 70 bytes per flow.
  }
  ◊li{The flow support unlimited concurrency.}
  ◊li{
    The notification feature adds a lot of complexity to the ledger implementation.
    The ledger might need to deal with unresponsive destinations and implement a retry policy for delivering notifications.
  }
  ◊li{
    The ledger sends the notification on-chain, making it very likely that the shop will receive the notification.
    Still, there is a possibility that the notification will not get through if the destination is overloaded.
  }
}
}

◊section{
◊section-title["transfer-notify"]{Transfer-fetch}
◊p{
  The transfer-fetch flow relies on the ability to request details of past transactions from the ledger.
  After I transfer tokens to the shop, specifying the ◊em{Invoice ID} as the transaction memo, the ledger issues a unique transaction identifier.
  I can then pass this identifier to the shop as proof of my payment.
  The shop can fetch transaction details directly from the ledger to validate the payment.
  Below is the interface we expect from the ledger.
}

◊source-code["candid"]{
service : {
  ◊em{// Transfers token ◊b{amount} from the account of the (implicit) ◊b{caller}}
  ◊em{// to the account specified by the principal.}
  ◊em{// Returns a unique transaction identifier.}
  ◊em{// Arguments:}
  ◊em{//   ◊b{amount} - the token amount to transfer.}
  ◊em{//   ◊b{to} - the receiver of the tokens.}
  ◊em{//   ◊b{memo} - an opaque identifier attached to the transaction.}
  ◊b{transfer}(record {
    amount : nat;
    to : principal;
    memo : opt blob;
  }) -> (nat);

  ◊em{// Retrieves details of the transaction with the specified identifier.}
  ◊em{// Arguments:}
  ◊em{//   ◊b{txid} - a unique transaction identifier.}
  ◊b{fetch}(txid : nat) -> (opt record {
    from : principal;
    to : principal;
    amount : nat;
    memo : opt blob;
  });
}
}

◊p{
  The flow proceeds as follows:
}
◊ol-circled{
  ◊li{In the negotiation phase, the webpage displays the payment details, a text field for the transaction identifier, and a big green ◊quoted{Done} button.}
  ◊li{
    In the payment phase, I use my wallet to execute the ◊code{transfer({to = Shop, amount = Price, memo = InvoiceID})} call on the ledger.
    If the transfer is successful, the transaction receipt contains a unique transaction identifier.
  }
  ◊li{
    I paste the transaction identifier into the text field and press the green button.
    Once the shop receives the notification with the transaction identifier, it fetches the transaction from the ledger and validates the amount and the memo.
    If the validation passes, the order is complete.
  }
}

◊figure[#:class "grayscale-diagram"]{
◊marginnote["mn-transfer-fetch-seq"]{
  A sequence diagram for the transfer-fetch payment flow.
}
◊p{◊img[#:src "/images/10-fetch-flow.png"]{}}
}

◊ul[#:class "arrows"]{
  ◊li{The ledger must process at least two messages: a ◊code{transfer} from me and a ◊code{fetch} request from the shop.}
  ◊li{
    The ledger charges one fee for my transfer.
    The transaction details are usually publicly available and require no access fee.
  }
  ◊li{The ledger does not need to store any additional information for the payment flow.}
  ◊li{The flow support unlimited concurrency.}
  ◊li{
    Transaction access interfaces are handy and ubiquitous.
    Little additional complexity is usually required to enable the flow.
  }
  ◊li{
    The failure cases are very similar to the ◊a[#:href "#invoice-account"]{invoice-account} flow, except that there is no easy way to monitor outstanding invoices.
    One possible recovery is constructing an index of all the ledger transactions and scanning for transfers matching the open orders.
  }
}
}

◊section{
◊section-title["conclusion"]{Conclusion}
◊p{
  We analyzed several payment flows for ledgers hosted on the Internet Computer.
  All the flows we discussed had ◊a[#:href "#payment-phases"]{three phases}: negotiation, payment, and notification.
}
◊p{
  Below is a table comparing the payment flows.
}
◊table[#:style "text-align: center;"]{
◊thead{
◊tr{
  ◊th{} ◊th{◊a[#:href "#invoice-account"]{invoice account}} ◊th{◊a[#:href "#approve-transfer-from"]{approve-transfer-from}} ◊th{◊a[#:href "transfer-notify"]{transfer-notify} ◊th{◊a[#:href "transfer-fetch"]{transfer-fetch}}}
}
}
◊tbody{
◊tr{◊td{Ledger messages} ◊td{2} ◊td{2} ◊td{2} ◊td{2}}
◊tr{◊td{Fees} ◊td{2} ◊td{2} ◊td{1½} ◊td{1}}
◊tr{◊td{Ledger memory per flow} ◊td{70} ◊td{68} ◊td{70} ◊td{0}}
◊tr{◊td{Concurrent payments} ◊td{◊check{}} ◊td{◊ballot-x{}} ◊td{◊check{}} ◊td{◊check{}}}
◊tr{◊td{Recurrent payments} ◊td{◊ballot-x{}} ◊td{◊check{}} ◊td{◊ballot-x{}} ◊td{◊ballot-x{}}}
◊tr{◊td{Ledger complexity} ◊td{simple} ◊td{moderate} ◊td{complex} ◊td{simple}}
◊tr{◊td{Failure recovery} ◊td{not easy} ◊td{ok} ◊td{hard but rare} ◊td{hard}}
}
}
◊p{
  So which flow is the best one?
  None of them is a clear winner on all fronts.
  You might prefer different flows based on your design goals and the application needs.
}
}