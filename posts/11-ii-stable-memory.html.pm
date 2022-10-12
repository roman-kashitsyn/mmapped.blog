#lang pollen

◊(define-meta title "IC internals: Internet Identity storage")
◊(define-meta keywords "ic")
◊(define-meta summary "How the Internet Identity canister uses its stable memory to achieve safe upgrades.")
◊(define-meta doc-publish-date "2022-10-12")
◊(define-meta doc-updated-date "2022-10-12")

◊section{
◊section-title["introduction"]{Introduction}
◊p{
  The Internet Identity canister innovated a passwordless approach to authentication on the ◊a[#:href "https://internetcomputer.org"]{Internet Computer} (IC).
  I was lucky to be among the first members of the team that launched this service.
  Despite the time shortage, the team pioneered a few engineering solutions, some of which later caught up in other services:
}
◊ul[#:class "arrows"]{
  ◊li{Stable memory as the primary storage.}
  ◊li{The ◊a[#:href "https://wiki.internetcomputer.org/wiki/HTTP_asset_certification"]{HTTP asset certification} protocol.}
  ◊li{The use of ◊a[#:href "https://internetcomputer.org/how-it-works/response-certification/"]{certified variables} for authentication.}
  ◊li{An observability system based on ◊a[#:href "https://prometheus.io/docs/introduction/overview/"]{Prometheus}.}
  ◊li{Canister integration testing in a simulated replica environment.}
  ◊li{End-to-end CI tests powered by ◊a[#:href "https://www.selenium.dev/"]{Selenium}.}
}
◊p{
  This article will explain how the Internet Identity canister uses its stable memory.
}
}

◊section{
◊section-title["ii-data-model"]{Internet Identity data model}
◊p{
  The Internet Identity service acts as a proxy between the browser's ◊a[#:href "https://webauthn.io/"]{authentication mechanism} and the Internet Computer authentication system.
  A user registers in the service by creating an ◊em{anchor} (a short number) and associating authentication devices, such as ◊a[#:href "https://en.wikipedia.org/wiki/YubiKey"]{Yubikey} or ◊a[#:href "https://en.wikipedia.org/wiki/Touch_ID"]{Apple Touch ID}, with that anchor.
  The Internet Identity canister stores these associations and presents a consistent identity to each DApp integrated with the authentication protocol.
}
◊figure[#:class "grayscale-diagram"]{
  ◊marginnote["mn-ii-model"]{
    The data model of the Internet Identity system.
    The system allocates a unique ◊em{anchor} (a short number) for each user.
    The user can attach one or more authentication devices to the anchor.
    The Internet Identity system allows users to log into DApps that support the authentication protocol.
    The DApps will see the same user identity (also known as the ◊a[#:href "https://internetcomputer.org/docs/current/references/ic-interface-spec/#principal"]{principal}) consistently, regardless of which device the user used for authentication.
  }
  ◊p[#:style "text-align:center;"]{◊img[#:src "/images/11-ii-model.png" #:width "50%" #:height "50%"]{}}
}
◊p{
  The Internet Identity service maintains three core data structures:
}
◊ol-circled{
  ◊li{A mapping from anchors to authentication devices and their attributes.}
  ◊li{A collection of frontend assets, such as the index page, JavaScript code, and images.}
  ◊li{A set of temporary certified delegations. Most delegations expire within a minute after the service issues them.}
}
}

◊section{
◊section-title["conventional-memory-management"]{Conventional canister state management}
◊p{
  The ◊a[#:href "/posts/06-ic-orthogonal-persistence.html"]{orthogonal persistence} feature of the IC greatly simplifies program state management.
  Yet it does not solve the problem of code upgrades◊sidenote["sn-upgrades"]{You can find more detail in the ◊a[#:href "/posts/06-ic-orthogonal-persistence.html#upgrades"]{Surviving upgrades} section of the post on orthogonal persistence.}.
  Most canister work around this issue by using ◊a[#:href "https://internetcomputer.org/docs/current/references/ic-interface-spec/#system-api-stable-memory"]{stable memory} as a temporary buffer during the code upgrade.
}

◊figure[#:class "grayscale-diagram"]{
  ◊marginnote["mn-conventional-upgrade"]{
    The conventional model of canister ◊a[#:href "https://internetcomputer.org/docs/current/references/ic-interface-spec/#system-api-upgrades"]{code upgrades}.
    In the pre-upgrade hook, the canister marshals its data into stable memory storage.
    In the post-upgrade hook, the canister unmarshals the contents of stable memory to reconstruct the convenient data representation.
  }
  ◊p[#:style "text-align:center;"]{◊img[#:src "/images/11-conventional-upgrade.png" #:alt "Conventional model of canister code upgrades" #:width "60%" #:height "60%"]{}}
}

◊p{
  This upgrade model works well for canisters that hold little data, usually up to a few hundred megabytes (the exact limit depends on the encoding scheme).
  However, if the state grows too large for the persistence roundtrip to fit into the upgrade ◊a[#:href "/posts/01-effective-rust-canisters.html#instruction-counter"]{instruction limit}, upgrading the canister might become complicated or impossible.
}
◊p{
  From the beginning, the Internet Identity team knew that the service must support millions of users and retain gigabytes of data.
  One way to achieve scalability is to spread the data across multiple canisters and ensure that each canister holds a reasonably-sized share of the state.
  However, the time constraint forced the team to keep the architecture simple and build the service as a monolithic backend canister◊sidenote["sn-sharding"]{Luckily, there is an easy way to extend the chosen monolithic design to support data sharding.}.
  That design has other advantages besides short time-to-market: atomic upgrades and the ease of deployment, testing, and monitoring.
}
}

◊section{
◊section-title["ii-stable-memory"]{Stable memory as primary storage}
◊p{
  To reconcile the monolithic design with fearless upgrades, the team arranged the ◊a[#:href "#ii-data-model"]{core data structures} in the following way:
}
◊ol-circled{
  ◊li{
    The mapping from anchor to devices lives directly in stable memory.
    Each anchor gets a fixed chunk of memory that is large enough to hold ten authentication devices (on average).
  }
  ◊li{
    The build process embeds the frontend assets directly into Internet Identity's WebAssembly binary, eliminating the need to carry those assets across upgrades.
  }
  ◊li{
    The canister discards all delegations on upgrades.
    This decision simplifies data management without affecting the user experience much.
  }
}
◊p{
  The canister arranges the anchor mapping directly in stable memory, updating the relevant sections incrementally with each user interaction.
  A good analogy with traditional computing would be updating data in files incrementally instead of loading them fully into memory and writing them back.
  The main difference is that stable memory is a much safer mechanism than file manipulations: you do not need to worry about data loss, partial writes, power outages, and disk corruption.
}
◊p{
  This design eliminates the need for a pre-upgrade hook: stable memory is already up-to-date when the upgrade starts.
  The post-upgrade hook does little work besides reading and validating a few bytes of the storage metadata.
}
◊figure[#:class "grayscale-diagram"]{
  ◊marginnote["mn-ii-storage-model"]{
    The Internet Identity storage model.
    The anchor data lives directly in stable memory.
    The pre-upgrade is unnecessary; the post-upgrade hook does little work.
  }
  ◊p[#:style "text-align:center;"]{◊img[#:src "/images/11-ii-upgrade-model.png" #:alt "The Internet Identity storage mode." #:width "60%" #:height "60%"]{}}
}

◊subsection-title["ii-memory-layout"]{The memory layout}
◊p{
  The Internet Identity canister divides the stable memory space into non-overlapping sections.
  The first section is the ◊em{header} holding the canister configuration, such as the random salt for hashing and the assigned anchor range.
  The rest of the memory is an array of ◊em{entries}; each entry corresponds to the data of a single anchor.
}
◊figure[#:class "grayscale-diagram"]{
  ◊marginnote["mn-ii-memory-layout"]{
    The Internet Identity stable memory layout.
    The system reserves the first 512 bytes for static configuration and divides the rest into 2KiB blocks.
    Each such block holds data associated with a single anchor.
   }
  ◊p[#:style "text-align:center;"]{◊img[#:src "/images/11-ii-layout.png" #:alt "The Internet Identity stable memory layout." #:width "80%" #:height "80%"]{}}
}

◊p{
  The size of the header section is 512 bytes; the layout reserves most of this space for future extensions.
  The following is the list of all header fields as of October 2022:
}
◊ol-circled{
  ◊li{
    ◊em{Magic} (3 bytes): a fixed string ◊code{"IIC"} ◊a[#:href "https://en.wikipedia.org/wiki/Magic_number_(programming)#Format_indicators"]{indicating} the Internet Identity stable memory layout.
  }
  ◊li{
    ◊em{Version} (1 byte): the version of the memory layout.
    If we need to change the layout significantly, the version will tell the canister how to interpret the data after the code upgrade.
  }
  ◊li{
    ◊em{Entry count} (4 bytes): the total number of anchors allocated so far.
  }
  ◊li{
    ◊em{Min anchor} (8 bytes): the value of the first anchor assigned to the canister.
    The canister allocates anchors sequentially, starting from this number.
  }
  ◊li{
    ◊em{Max anchor} (8 bytes): the value of the largest anchor assigned to the canister.
    The canister becomes full and stops allocating anchors when ◊code{MinAnchor + EntryCount = MaxAnchor}.
  }
  ◊li{
    ◊em{Salt} (32 bytes): salt for hashing.
    The canister initializes the salt upon the first request by issuing a ◊a[#:href "https://internetcomputer.org/docs/current/references/ic-interface-spec/#ic-raw_rand"]{◊code{raw_rand}} call.
  }
}
◊p{
  Further sections are all 2 KiB in size and contain anchor data encoded as ◊a[#:href "https://github.com/dfinity/candid"]{Candid}.
  Entry at index ◊code{N} holds information associated with anchor ◊code{MinAnchor + N}, where ◊code{MinAnchor} comes from the header.
  The first two bytes of each entry determine the size of the encoded blob.
}
◊subsection-title["ii-anchor-read-example"]{Example: lookup anchor devices}
◊p{
  To get a feeling for how this layout works in practice, let us assume that the canister holds the range of anchors between ◊code{MinAnchor = 10_000} and ◊code{MaxAnchor = 1_000_000} and already allocated ◊code{NumEntries = 20_000} anchors.
  Below are the steps the canister must perform to fetch the list of devices for anchor ◊code{12345}:
}
◊ol-circled{
  ◊li{
    Look up the range of metadata from the header.
    The requested anchor ◊code{12345} is in the range of ◊quoted{live} anchors between ◊code{10_000} and ◊code{30_000} (◊code{MinAnchor} and ◊code{MinAnchor + NumEntries}, correspondingly).
    Entry ◊code{2345} (◊code{12345 - MinAnchor}) holds the data for anchor ◊code{12345}.
  }
  ◊li{
    Read the first two bytes at offset ◊code{EntryStart = 512 bytes + 2345 * 2MiB} as a 16-bit integer (◊a[#:href "https://en.wikipedia.org/wiki/Endianness"]{little-endian}).
    The decoded value ◊code{N} determines the size of the blob we have to read next.
  }
  ◊li{
    Read ◊code{N} bytes starting at offset ◊code{EntryStart + 2}.
    Decode the bytes as a Candid structure containing the list of authentication devices.
  }
}
}

◊section{
◊section-title["code-pointers"]{Code pointers}
◊ul[#:class "arrows"]{
◊li{The data type describing the ◊a[#:href "https://github.com/dfinity/internet-identity/blob/62afdcbd74b1de1d9ab41c9f856e2319661a32cf/src/internet_identity/src/state.rs#L20-L31"]{authentication device attributes}.}
◊li{
  ◊a[#:href "https://github.com/dfinity/internet-identity/blob/62afdcbd74b1de1d9ab41c9f856e2319661a32cf/src/internet_identity/src/storage.rs"]{The stable data storage} implementation.
  I am sure you will find this code easy to read now that you know its story.
}
}
}