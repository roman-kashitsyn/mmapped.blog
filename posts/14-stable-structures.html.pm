#lang pollen

◊(define-meta title "Tutorial: stable-structures")
◊(define-meta keywords "ic, rust")
◊(define-meta summary "An introduction into the stable-structures library.")
◊(define-meta doc-publish-date "2022-01-20")
◊(define-meta doc-updated-date "2022-01-20")

◊epigraph{
  ◊blockquote[#:cite "https://youtu.be/rX0ItVEVjHc?t=1360"]{
    ◊p{Only purpose of any code is to transform data.}
    ◊footer{Mike Acton, ◊quoted{Data-Oriented Design and C++}, CppCon 2014}
  }
}


◊section{
◊section-title["introduction"]{Introduction}
◊p{
  Canisters hosted on the Internet Computer (IC) are mutable: canister controllers can upgrade the code to add new features or fix bugs without changing the canister's identity.
}
◊p{
  Since the ◊a[#:href "/posts/06-ic-orthogonal-persistence.html#upgrades"]{orthogonal persistence} feature cannot handle upgrades, the IC allows canisters to use additional storage, called ◊em{stable memory}, to facilitate the data transfer between code versions.
  The ◊a[#:href "/posts/11-ii-stable-memory.html#conventional-memory-management"]{conventional approach} to canister state persistence is to serialize the entire state to stable memory in the ◊code{pre_upgrade} hook and decode it back in the ◊code{post_upgrade} hook.
  This approach is easy to implement and works well for relatively small datasets.
  Unfortunately, it does not scale well and can render a canister non-upgradable, so I ◊a[#:href "/posts/01-effective-rust-canisters.html#stable-memory-main"]{recommend} using stable memory as the primary storage when possible.
}
◊p{
  The ◊a[#:href "https://github.com/dfinity/stable-structures"]{ic-stable-structures} library aims to simplify managing data structures directly in stable memory.
  This article explains the philosophy behind the library and how to use it effectively.
}
}


◊section{
◊section-title["design-principles"]{Design principles}
◊epigraph{
  ◊blockquote[#:cite "https://youtu.be/rX0ItVEVjHc?t=1464"]{
    ◊p{Understand the data to understand the problem.}
    ◊footer{Mike Acton, ◊quoted{Data-Oriented Design and C++}, CppCon 2014}
  }
}

◊p{
  Software designs reflect their creators' values.
  The following principles shaped the ◊code{stable-structures} library design.
}
◊ul[#:class "arrows"]{
  ◊li{
    ◊em[#:id "radical-simplicity"]{Radical simplicity.}
    Programming stable memory is significantly easier than working with conventional file systems.
    The IC solves many issues with which any good storage must deal: data integrity, partial writes, power outages, and atomicity of multiple writes.
    Even with all these issues sorted out, complicated designs would be hard to implement, debug, and maintain.
    Each data structure follows the most straightforward design that solves the problem at hand.
  }
  ◊li{
    ◊em[#:id "backward-compatibility"]{Backward compatibility.}
    Upgrading the library version must preserve the data.
    All data structures have a metadata section with the layout version.
    Newer implementations will respect old layouts and should not require data migration.
  }
  ◊li{
    ◊em{No ◊code{pre_upgrade} hooks.}
    A bug in the ◊code{pre_upgrade} hook can make your canister ◊a[#:href "/posts/01-effective-rust-canisters.html#upgrade-hook-panics"]{non-upgradable}.
    The best way to avoid this issue is not to have a ◊code{pre_upgrade} hook.
  }
  ◊li{
    ◊em{Limited blast radius.}
    If a single data structure has a bug, it should not corrupt the contents of other data structures.
  }
  ◊li{
    ◊em{No reallocation.}
    Moving large amounts of data is expensive and can lead to prohibitively high cycle consumption.
    All data structures must manage their memory without costly moves.
  }
  ◊li{
    ◊em{Compatibility with ◊a[#:href "https://github.com/WebAssembly/multi-memory/blob/master/proposals/multi-memory/Overview.md"]{multi-memory} WebAssembly.}
    The design should work when canisters have multiple stable memories since this feature is on the ◊a[#:href "https://forum.dfinity.org/t/proposal-wasm-native-stable-memory/15966#proposal-7"]{IC roadmap}.
  }
}
◊p{
  As a result of these goals, using the library requires planning and understanding your data shape.
  For example, you might need to set an ◊a[#:href "#max-size-attribute"]{upper bound} on a value size that you cannot adjust without data migration.
  Or you might have to decide how many memory pages you want to allocate for canister configuration.
  There are other libraries with similar goals whose authors chose a slightly different set of trade-offs, such as ◊code-ref["https://crates.io/crates/ic-stable-memory"]{ic-stable-memory}.
}
}


◊section{
◊section-title["abstractions"]{Abstractions}
◊subsection-title["memory"]{Memory}
◊p{
  The core abstraction of the library is the ◊code-ref["https://docs.rs/ic-stable-structures/latest/ic_stable_structures/trait.Memory.html"]{Memory} trait that models a WebAssembly ◊a[#:href "https://webassembly.github.io/multi-memory/core/exec/runtime.html#memory-instances"]{memory instance}◊sidenote["sn-multiple-memories"]{
    That design decision is not a coincidence.
    Eventually, canisters will access multiple stable memories, and each data structure might reside in a dedicated memory instance.
  }.
}
◊source-code["rust"]{
pub trait ◊b{Memory} {
    ◊em{/// Equivalent to WebAssembly memory.size.}
    fn ◊b{size}(&self) -> u64;

    ◊em{/// Equivalent to WebAssembly memory.grow.}
    fn ◊b{grow}(&self, pages: u64) -> i64;

    ◊em{/// Copies bytes from this memory to the heap (in Wasm, memory 0).}
    fn ◊b{read}(&self, offset: u64, dst: &mut [u8]);

    ◊em{/// Writes bytes from the heap (in Wasm, memory 0) to this memory.}
    fn ◊b{write}(&self, offset: u64, src: &[u8]);
}
}
◊figure[#:class "grayscale-diagram"]{
◊marginnote["mn-memory-trait"]{
  The ◊code-ref["https://docs.rs/ic-stable-structures/latest/ic_stable_structures/trait.Memory.html"]{Memory} trait models the WebAssembly ◊a[#:href "https://webassembly.github.io/multi-memory/core/exec/runtime.html#memory-instances"]{memory instance}.
  It allocates memory in 64KiB pages: the zero page spans addresses ◊code{0◊ndash{}ffff}, the first page◊mdash{}◊code{10000◊ndash{}1ffff}, etc.
}
◊(embed-svg "images/14-memory.svg")
}

◊p{
  Some instances of the ◊code{Memory} trait are:
}
◊ul[#:class "arrows"]{
  ◊li{
    The ◊code-ref["https://github.com/dfinity/stable-structures/blob/3d22d483b9c55b79f7b869e3cf930883687d9fda/src/ic0_memory.rs"]{Ic0StableMemory} type delegates calls to the ◊a[#:href "https://internetcomputer.org/docs/current/references/ic-interface-spec#system-api-stable-memory"]{IC System API}.
  }
  ◊li{
    ◊code-ref["https://github.com/dfinity/stable-structures/blob/3d22d483b9c55b79f7b869e3cf930883687d9fda/src/vec_mem.rs#L11"]{RefCell<Vec<u8>>} implements the ◊code{Memory} interface for a byte array.
    This type is helpful for unit tests.
  }
  ◊li{
    The ◊code-ref["https://docs.rs/ic-stable-structures/latest/ic_stable_structures/type.DefaultMemoryImpl.html"]{DefaultMemoryImpl} type alias points to ◊code{Ic0StableMemory} when compiled to WebAssembly.
    Otherwise it expands to a memory backed by a byte array.
    This alias allows you to compile your canister to ◊a[#:href "/posts/01-effective-rust-canisters.html#target-independent"]{native code} with minimal effort.
  }
  ◊li{
    ◊code-ref["https://docs.rs/ic-stable-structures/latest/ic_stable_structures/struct.RestrictedMemory.html"]{RestrictedMemory} is a view of another memory restricted to a contiguous page range.
    You can use this type to split a large memory into non-intersecting regions if you know the size of the chunk in advance.
    ◊code{RestrictedMemory} works best for allocating relatively small fixed-size memories.
  }
}
◊figure[#:id "restricted-memory" #:class "grayscale-diagram"]{
◊marginnote["mn-restricted-memory"]{
  Restricted memory limits the primary memory to a contiguous page range.
  The example on the diagram demonstrates splitting a 5-page primary memory into two memories: the first memory spans pages from zero to two (exclusive), and the second memory spans pages from two to five (exclusive).
}
◊(embed-svg "images/14-restricted-memory.svg")
}
◊p{
  The most powerful and convenient way to create memories is to use the ◊code-ref["https://docs.rs/ic-stable-structures/latest/ic_stable_structures/memory_manager/struct.MemoryManager.html"]{MemoryManager}.
  This utility interleaves up to 255 non-intersecting memories in a single address space, acting similarly to a virtual memory subsystem in modern operating systems.
  The memory manager uses part of the parent memory to keep a dynamic translation table assigning page ranges to virtual memories.
}
◊figure[#:id "memory-manager" #:class "grayscale-diagram"]{
◊marginnote["mn-memory-manager"]{
  The memory manager interleaves multiple virtual memories in a single primary memory, using the first few pages to store metadata.
}
◊(embed-svg "images/14-memory-manager.svg")
}
◊p{
  Virtual memories have a non-contiguous representation, so a single write can translate to multiple system calls.
}

◊subsection-title["storable-types"]{Storable types}
◊p{
  The library does not impose any serialization format on you and does not provide a default.
  Depending on your needs, you might prefer ◊a[#:href "https://github.com/dfinity/candid"]{Candid}, ◊a[#:href "https://developers.google.com/protocol-buffers"]{Protocol Buffers}, ◊a[#:href "https://cbor.io/"]{CBOR}, ◊a[#:href "https://borsh.io/"]{Borsh}, ◊a[#:href "https://en.wikipedia.org/wiki/X.690#DER_encoding"]{DER}, or something else.
  The ◊code{Storable} trait abstracts data structures over your choice of serialization format.
}
◊figure{
◊marginnote["mn-storable-trait"]{
  The ◊code{Storable} trait abstracts data structures over your choice of serialization format.
}
◊source-code["rust"]{
pub trait ◊b[#:id "storable-trait"]{Storable} {
    ◊em{/// Serializes a value of a storable type into bytes.}
    fn ◊b{to_bytes}(&self) -> Cow<'_, [u8]>;

    ◊em{/// Deserializes a value of a storable type from a byte array.}
    ◊em{///}
    ◊em{/// ◊b{REQUIREMENT}: Self::from_bytes(self.to_bytes().to_vec()) == self}
    fn ◊b{from_bytes}(bytes: Cow<[u8]>) -> Self;
}
}
}
◊p{
  Some data structures, such as ◊a[#:href "stable-vector"]{stable vectors}, need to know how much memory they must allocate for each instance of your storable type.
  Such types rely on an extension of this trait, providing this necessary metadata, ◊code{BoundedStorable}.
  ◊code{BoundedStorable} types are analogous in their function to ◊code-ref["https://doc.rust-lang.org/std/marker/trait.Sized.html"]{Sized} types, except that the compiler cannot deduce serialized sizes for you.
}
◊figure{
◊marginnote["mn-storable-trait"]{
  Some data structures require their values to implement ◊code{BoundedStorable} trait to know how much space they need to allocate for each item.
}
◊source-code["rust"]{
pub trait ◊b[#:id "bounded-storable-trait"]{BoundedStorable}: ◊code-ref["#storable-trait"]{◊b{Storable}} {
    ◊em{/// The maximum slice length that ◊b{to_bytes} can return.}
    ◊em{///}
    ◊em{/// ◊b{REQUIREMENT}: self.to_bytes().len() ≤ Self::MAX_SIZE as usize}
    const ◊b[#:id "max-size-attribute"]{MAX_SIZE}: u32;

    ◊em{/// Whether all values of this type have the same length (equal to Self::MAX_SIZE)}
    ◊em{/// when serialized. If you are unsure about this flag, set it to ◊b{false}.}
    ◊em{///}
    ◊em{/// ◊b{REQUIREMENT}: Self::IS_FIXED_SIZE ⇒ self.to_bytes().len() == Self::MAX_SIZE as usize}
    const ◊b[#:id "is-fixed-size-attribute"]{IS_FIXED_SIZE}: bool;
}
}
}
◊p{
  The library implements these traits for a few basic types, such as integers, fixed-size arrays, and tuples, allowing you to get away without serialization libraries if you store only primitives.
  It also provides efficient variable-size bounded byte arrays, the ◊code{Blob<N>} type, where ◊code{N} is the maximal number of bytes this type can hold.
  For example, you can persist an IC ◊a[#:href "https://internetcomputer.org/docs/current/references/ic-interface-spec#principal"]{principal} as a ◊code{Blob<29>}.
}
}


◊section{
◊section-title["data-structures"]{Data structures}
◊p{
  The heart of the ◊code{stable-structures} library is a collection of data structures, each spanning one or more ◊a[#:href "#memory"]{memories}.
}
◊p{
  Stable structures do not compose◊sidenote["sn-nesting-restriction"]{
      The reason for this restriction is simplicity: most data structures are significantly easier to implement correctly and efficiently, assuming they can span an entire ◊a[#:href "#memory"]{memory}.
  }.
  For example, you cannot construct a stable map containing stable vectors as values.
  Many conventional storage systems impose the same restriction.
  For example, SQL databases do not allow tables to hold other tables as values, and Redis does not allow the nesting of its ◊a[#:href "https://redis.io/docs/data-types/"]{data types}.
}
◊p{
  Using ◊a[#:href "https://en.wikipedia.org/wiki/Composite_key"]{composite keys} or defining several data structures linked with ◊a[#:href "https://en.wikipedia.org/wiki/Foreign_key"]{foreign keys}, you can work around the restriction.
}
◊figure{
◊source-code["bad"]{
◊em{// ◊b{BAD}: stable structures do not support nesting.}
type BalanceMap = StableBTreeMap<Principal, StableBTreeMap<Subaccount, Tokens>>;
}
◊source-code["good"]{
◊em{// ◊b{GOOD}: use a composite key (a tuple) to avoid nesting.}
◊em{// Use a ◊a[#:href "#range-scan-example"]{◊b{range scan}} to find all subaccounts of a principal.}
type BalanceMap = StableBTreeMap<(Principal, Subaccount), Tokens>;
}
◊source-code["bad"]{
◊em{// ◊b{BAD}: stable structures do not support nesting.}
type TxIndex = StableBTreeMap<Principal, StableVector<Transaction>>;
}
◊source-code["good"]{
◊em{// ◊b{GOOD}: use a composite key to avoid nesting.}
◊em{// Use a ◊a[#:href "#range-scan-example"]{◊b{range scan}} to find all transactions of a principal.}
type TxIndex = StableBTreeMap<(Principal, TxId), Transaction>;
}
}

◊p{
  Let us examine the available data structures in detail.
}

◊subsection-title["stable-cell"]{Stable cell}
◊p{
  A ◊a[#:href "https://docs.rs/ic-stable-structures/latest/ic_stable_structures/cell/struct.Cell.html"]{Cell} represents a single value stored in stable memory in serialized form.
  Cell's contents in stable memory updates every time you change the underlying value.
}
◊figure{
◊marginnote["mn-log-interface"]{
  The core interface of the ◊code{Cell} stable structure.
}
◊source-code["rust"]{
impl<T: ◊code-ref["#storable-trait"]{Storable}, M: ◊code-ref["#memory"]{Memory}> struct ◊b{Cell}<T, M> {
    ◊em{/// Returns the current cell value.}
    ◊em{/// Complexity: O(1).}
    pub fn ◊b{get}(&self, idx: usize) -> Option<T>;

    ◊em{/// Updates the cell value.}
    ◊em{/// Complexity: O(value size).}
    pub fn ◊b{set}(&mut self, value: T) -> Result<T, ValueError>;
}
}
}
◊figure[#:class "grayscale-diagram"]{
  ◊marginnote["mn-cell-figure"]{
    A ◊code{Cell} persists a single value in stable memory and caches it on the heap.
    The serialized value and the value on the heap are always in sync.
  }
  ◊(embed-svg "images/14-cell.svg")
}
◊p{
  The primary use case for cells is storing canister configuration:
}
◊ul[#:class "arrows"]{
  ◊li{The ICRC-1 Ledger Archive canister persists its initialization arguments in a ◊a[#:href "https://github.com/dfinity/ic/blob/9cdb1e62bcd199f28ae0005ed3f762487a1454df/rs/rosetta-api/icrc1/archive/src/main.rs#L49"]{cell}.}
  ◊li{The Internet Identity Archive canister holds its init arguments in a ◊a[#:href "https://github.com/dfinity/internet-identity/blob/b66fe925fb0a337b09aaaa5beaf1a60994b19f14/src/archive/src/main.rs#L85"]{cell}.}
}

◊subsection-title["stable-vec"]{Stable vector}
◊p{
  A ◊code{Vec} is a growable mutable array similar to ◊code-ref["https://doc.rust-lang.org/std/vec/struct.Vec.html"]{std::vec::Vec}.
  A stable vector stores its items by value, so it must know how much space it needs to allocate for each item, hence the ◊code-ref["#bounded-storable-trait"]{BoundedStorable} bound on the item type.
}
◊p{
  Stable vector takes advantage of the ◊code-ref["#is-fixed-size-attribute"]{T::IS_FIXED_SIZE} attribute of the item type.
  If the value size is not fixed, the vector allocates a few extra bytes to store the actual entry size and the ◊code-ref["#max-size-attribute"]{T::MAX_SIZE} bytes required for each value.
  If all the values are the same size, the vector implementation uses ◊code-ref["#max-size-attribute"]{T::MAX_SIZE} for the item slot, saving up to 4 bytes per entry.
  This reduction is primarily helpful for vectors of primitives (e.g., ◊code{StableVec<u64>}).
}
◊figure{
◊marginnote["mn-log-interface"]{
  The core interface of the ◊code{Vec} stable structure.
}
◊source-code["rust"]{
impl<T: ◊code-ref["#storable-types"]{BoundedStorable}, Data: ◊code-ref["#memory"]{Memory}> struct ◊b{Vec}<T, Memory> {
    ◊em{/// Adds a new item at the vector's back.}
    ◊em{/// Complexity: O(T::MAX_SIZE).}
    pub fn ◊b{push}(&self, item: &T) -> Result<usize, GrowFailed>;

    ◊em{/// Removes an item from the vector's back.}
    ◊em{/// Complexity: O(T::MAX_SIZE).}
    pub fn ◊b{pop}(&self) -> Option<T>;

    ◊em{/// Returns the item at the specified index.}
    ◊em{/// Complexity: O(T::MAX_SIZE).}
    pub fn ◊b{get}(&self, index: usize) -> Option<T>;

    ◊em{/// Updates the item at the specified index.}
    ◊em{/// Complexity: O(T::MAX_SIZE).}
    pub fn ◊b{set}(&self, index: usize, item: &T);

    ◊em{/// Returns the number of items in the vector.}
    ◊em{/// Complexity: O(1).}
    pub fn ◊b{len}() -> usize;
}
}
}
◊figure[#:class "grayscale-diagram"]{
  ◊marginnote["mn-log-figure"]{
    A ◊code{Vec} is a growable mutable array.
    The data representation depends on the ◊code{IS_FIXED_WIDTH} attribute of the item type.
    If the type's representation is not fixed-width, the vector implementation must record each entry's length.
  }
  ◊(embed-svg "images/14-vec.svg")
}
◊p{
  The ◊a[#:href "/posts/11-ii-stable-memory.html#ii-memory-layout"]{stable structure} powering the Internet Identity service is a stable vector in disguise, though a less generic one.
}

◊subsection-title["stable-log"]{Stable log}
◊p{
  A ◊a[#:href "https://docs.rs/ic-stable-structures/latest/ic_stable_structures/log/struct.Log.html"]{Log} is an append-only list of arbitrary-sized values, similar to ◊a[#:href "https://redis.io/docs/data-types/streams/"]{streams} in Redis.
  The log requires two memories: the ◊quoted{index} storing entry offsets and the ◊quoted{data} storing raw entry bytes.
  The number of instructions needed to access old and append new entries does not depend on the number of items in the log, only on the entry size.
}
◊figure{
◊marginnote["mn-log-interface"]{
  The core interface of the ◊code{Log} stable structure.
}
◊source-code["rust"]{
impl<T, Index, Data> struct ◊b{Log}<T, Index, Data>
where
  T: ◊code-ref["#storable-trait"]{Storable},
  Index: ◊code-ref["#memory"]{Memory},
  Data: ◊code-ref["#memory"]{Memory},
{
    ◊em{/// Adds a new entry to the log.}
    ◊em{/// Complexity: O(entry size).}
    pub fn ◊b{append}(&self, bytes: &T) -> Result<usize, WriteError>;

    ◊em{/// Returns the entry at the specified index.}
    ◊em{/// Complexity: O(entry size).}
    pub fn ◊b{get}(&self, idx: usize) -> Option<T>;

    ◊em{/// Returns the number of entries in the log.}
    ◊em{/// Complexity: O(1).}
    pub fn ◊b{len}() -> usize;
}
}
}
◊figure[#:class "grayscale-diagram"]{
  ◊marginnote["mn-log-figure"]{
    A ◊code{Log} is an append-only list of values.
    Logs need two memories: the ◊quote{index} memory storing value offsets and the ◊quoted{data} memory storing raw entries.
    The image depicts a log with two values: the first entry is 100 bytes long, and the second entry is 200 bytes long.
  }
  ◊(embed-svg "images/14-log.svg")
}
◊p{
  The log is a versatile data structure that can be helpful in almost any application:
}
◊ul[#:class "arrows"]{
  ◊li{
    The ICRC-1 Ledger Archive canister stores archived transactions in a ◊a[#:href "https://github.com/dfinity/ic/blob/9cdb1e62bcd199f28ae0005ed3f762487a1454df/rs/rosetta-api/icrc1/archive/src/main.rs#L58"]{stable log}.
  }
  ◊li{
    The Internet Identity Archive canister holds events in a ◊a[#:href "https://github.com/dfinity/internet-identity/blob/b66fe925fb0a337b09aaaa5beaf1a60994b19f14/src/archive/src/main.rs#L90"]{stable log}.
  }
  ◊li{
    The Chain-Key Bitcoin Minter canister persists all state modifications in a ◊a[#:href "https://github.com/dfinity/ic/blob/6cc83edf2cad91ca1bdbe8f7965060a9ef1d1960/rs/bitcoin/ckbtc/minter/src/storage.rs#L21"]{stable log}.
    Replaying events from the log is the minter's primary upgrade mechanism.
  }
}

◊subsection-title["stable-btree"]{Stable B-tree}
◊p{
  The ◊code-ref["https://docs.rs/ic-stable-structures/latest/ic_stable_structures/btreemap/struct.BTreeMap.html"]{BTreeMap} stable structure is an associative container that can hold any ◊a[#:href "#storable-types"]{bounded storable type}.
  The map must know the sizes of the keys and values because it allocates nodes from a pool of fixed-size tree nodes◊sidenote["sn-"]{
    The ◊a[#:href "https://github.com/dfinity/stable-structures/blob/ed2fb6de50e56d2f93e67c2bfaa170fa4b1be60a/src/btreemap/allocator.rs#L13"]{tree allocator} is a ◊a[#:href "https://en.wikipedia.org/wiki/Free_list"]{free-list} allocator, the ◊a[#:href "#radical-simplicity"]{simplest allocator} capable of freeing memory.
  }.
}
◊p{
  The interface of stable ◊code{BTreeMap} will look familiar to any seasoned Rust programmer.
}
◊figure{
◊marginnote["mn-log-interface"]{
  The core interface of the ◊code{BTreeMap} stable structure.
}
◊source-code["rust"]{
impl<K, V, M> struct ◊b{BTreeMap}<K, V, M>
where
  K: ◊code-ref["#bounded-storable-trait"]{BoundedStorable} + Ord + Clone,
  V: ◊code-ref["#bounded-storable-trait"]{BoundedStorable},
  M: ◊code-ref["#memory"]{Memory},
{
    ◊em{/// Adds a new entry to the map.}
    ◊em{/// Complexity: O(log(N) * K::MAX_SIZE + V::MAX_SIZE).}
    pub fn ◊b{insert}(&self, key: K, value: V) -> Option<V>;

    ◊em{/// Returns the value associated with the specified key.}
    ◊em{/// Complexity: O(log(N) * K::MAX_SIZE + V::MAX_SIZE).}
    pub fn ◊b{get}(&self, key: &K) -> Option<V>;

    ◊em{/// Removes an entry from the map.}
    ◊em{/// Complexity: O(log(N) * K::MAX_SIZE + V::MAX_SIZE).}
    pub fn ◊b{remove}(&self, key: &K) -> Option<V>;

    ◊em{/// Returns an iterator over the entries in the specified key range.}
    pub fn ◊b{range}(&self, range: impl RangeBounds<K>) -> impl Iterator<Item = (K, V)>;

    ◊em{/// Returns the number of entries in the map.}
    ◊em{/// Complexity: O(1).}
    pub fn ◊b{len}() -> usize;
}
}
}
◊figure[#:class "grayscale-diagram"]{
  ◊marginnote["mn-btree"]{
    A ◊code{BTreeMap} is an associative container storing data in fixed-size dynamically-allocated ◊em{nodes}.
    Each node stores an array of key-value mappings ordered by key.
    The tree uses the ◊a[#:href "https://en.wikipedia.org/wiki/Free_list"]{free-list} technique for allocating and freeing nodes.
    Dotted boxes represent the logical tree structure.
  }
  ◊(embed-svg "images/14-btree.svg")
}
◊p{
  If you need a ◊code{BTreeSet<K>}, you can use ◊code{BTreeMap<K, ()>} instead.
}
◊p{
  The ◊code{range} method is handy for selecting relevant data from a large data set.
}

◊figure[#:id "range-scan-example"]{
◊marginnote["mn-range-scan-example"]{
  Two examples of using the ◊code{StableBTreeMap::range} method.
}
◊source-code["rust"]{
◊em{/// Selects all subaccounts of the specified principal.}
fn ◊b{principal_subaccounts}(
  balance_map: &StableBTreeMap<(Principal, Subaccount), Tokens>,
  principal: Principal,
) -> impl Iterator<Item = (Subaccount, Tokens)> + '_ {
  balance_map
    .◊b{range}((principal, Subaccount::default())..)
    .take_while(|((p, _), )| p == principal)
    .map(|((_, s), t)| (s, t))
}

◊em{/// Selects a transaction range for the specified principal.}
fn ◊b{principal_tx_range}(
  tx_index: &StableBTreeMap<(Principal, TxId), Transaction>,
  principal: Principal,
  start: TxId,
  len: usize,
) -> impl Iterator<Item = Transaction> + '_ {
  tx_index
    .◊b{range}((principal, start)..)
    .take(len)
    .map(|((_, _), tx)| tx)
}
}
}
}


◊section{
◊section-title["constructing-ss"]{Constructing stable structures}
◊p{
  We have to declare stable structures before we can use them.
  Each data structure ◊code{T} in the library declares at least three constructors:
}
◊ul[#:class "arrows"]{
  ◊li{◊code{T::new} allocates a new copy of ◊code{T} in the given ◊a[#:href "#memory"]{memory}, potentially overwriting previous memory content.}
  ◊li{◊code{T::load} recovers a previously constructed ◊code{T} from the given ◊a[#:href "#memory"]{memory}.}
  ◊li{◊code{T::init} is a ◊a[#:href "https://en.wikipedia.org/wiki/DWIM"]{DWIM} constructor acting as ◊code{T::new} if the given ◊a[#:href "#memory"]{memory} is empty and as ◊code{T::load} otherwise.}
}
◊p{
  In practice, most canisters need only ◊code{T::init}.
}
}


◊section{
◊section-title["tying-together"]{Tying it all together}
◊p{
  This section contains an example of declaring several data structures for a ledger canister compatible with the ◊a[#:href "https://github.com/dfinity/ICRC-1/blob/3c64844bc6219e1d07ce05e27ec636df1e562114/standards/ICRC-1/README.md"]{ICRC-1} specification.
  We will need three collections:
}
◊ol-circled{
  ◊li{
    A ◊code-ref["#stable-cell"]{Cell} to store the ledger metadata.
  }
  ◊li{
    A ◊code-ref["#stable-btree"]{StableBTreeMap} to map accounts ◊sidenote["sn-account"]{An ◊a[#:href "https://github.com/dfinity/ICRC-1/blob/3c64844bc6219e1d07ce05e27ec636df1e562114/standards/ICRC-1/README.md#account"]{account} is a pair of a principal and a 32-byte subaccount.} to their current balance.
  }
  ◊li{A ◊code-ref["#stable-log"]{StableLog} for transaction history.}
}
◊p{
  The ledger metadata is relatively small; it should fit into two megabytes or sixteen WebAssembly memory pages.
  We will allocate the metadata cell in a ◊a[#:href "#restricted-memory"]{restricted memory}, partitioning the rest of the stable memory between the accounts map and the log using the ◊a[#:href "#memory-manager"]{memory manager}.
}
◊p{
  Let us put these ideas to code.
  First, we must import a few type definitions from the library.
}

◊source-code["rust"]{
use ic_stable_structures::{
  DefaultMemoryImpl as DefMem,
  RestrictedMemory,
  StableBTreeMap,
  StableCell,
  StableLog,
  Storable,
};
use ic_stable_structures::memory_manager::{
  MemoryId,
  MemoryManager as MM,
  VirtualMemory,
};
use ic_stable_structures::storable::Blob;
use std::borrow::Cow;
use std::cell::RefCell;
}

◊p{
  Next, let us define the types of data we will store in our stable structures.
  I omit the field definitions because they are not essential for understanding the example.
  We derive serialization boilerplate for the ◊code{Metadata} and ◊code{Tx} types using the ◊a[#:href "https://serde.rs/"]{serde} framework.
}

◊source-code["rust"]{
type Account = (Blob<29>, [u8; 32]);
type Amount = u64;

#[derive(serde::Serialize, serde::Deserialize)]
struct ◊b{Metadata} { /* … */ }

#[derive(serde::Serialize, serde::Deserialize)]
enum ◊b{Tx} {
  Mint { /* … */ },
  Burn { /* … */ },
  Transfer { /* … */ },
}
}

◊p{
  The next step is to decide on the data serialization format.
  I use ◊a[#:href "https://cbor.io/"]{Concise Binary Object Representation} in the example because this encoding served me well in production.
  Instead of implementing the ◊code-ref["#storable-trait"]{Storable} trait for ◊code{Metadata} and ◊code{Tx}, I define a generic wrapper type ◊code{Cbor<T>} that I use for all types I want to encode as ◊smallcaps{cbor} and implement ◊code-ref["#storable-trait"]{Storable} only for the wrapper.
  I also implement ◊code-ref["https://doc.rust-lang.org/std/ops/trait.Deref.html"]{std::ops::Deref} to improve the ergonomics of the wrapper type.
}

◊source-code["rust"]{
◊em{/// A helper type implementing Storable for all}
◊em{/// serde-serializable types using the CBOR encoding.}
#[derive(Default)]
struct ◊b{Cbor}<T>(pub T)
where T: serde::Serialize + serde::de::DeserializeOwned;

◊b{impl}<T> std::ops::Deref for ◊b{Cbor}<T>
where T: serde::Serialize + serde::de::DeserializeOwned
{
  type Target = T;

  fn deref(&self) -> &Self::Target { &self.0 }
}

◊b{impl}<T> ◊code-ref["#storable-trait"]{Storable} for ◊b{Cbor}<T>
where T: serde::Serialize + serde::de::DeserializeOwned
{
  fn to_bytes(&self) -> Cow<[u8]> {
    let mut buf = vec![];
    ◊code-ref["https://docs.rs/ciborium/0.2.0/ciborium/ser/fn.into_writer.html"]{ciborium::ser::into_writer}(&self.0, &mut buf).unwrap();
    Cow::Owned(buf)
  }

  fn from_bytes(bytes: Cow<[u8]>) -> Self {
    Self(◊code-ref["https://docs.rs/ciborium/0.2.0/ciborium/de/fn.from_reader.html"]{ciborium::de::from_reader}(bytes.as_ref()).unwrap())
  }
}
}
◊p{
  The final and most important part is defining stable structures as ◊a[#:href "/posts/01-effective-rust-canisters.html#use-threadlocal"]{global canister variables}.
  Note the use of ◊code-ref["#restricted-memory"]{RestrictedMemory} to split the canister memory into two non-intersecting regions and ◊code-ref["#memory-manager"]{MemoryManager} (abbreviated as ◊code{MM}) to interleave multiple data structures in the second region.
}
◊source-code["rust"]{
◊em{// NOTE: ensure that all memory ids are unique and}
◊em{// do not change across upgrades!}
const ◊b{BALANCES_MEM_ID}: MemoryId = MemoryId::new(0);
const ◊b{LOG_INDX_MEM_ID}: MemoryId = MemoryId::new(1);
const ◊b{LOG_DATA_MEM_ID}: MemoryId = MemoryId::new(2);

◊em{// NOTE: we allocate the first 16 pages (about 2 MiB) of the}
◊em{// canister memory for the metadata.}
const ◊b{METADATA_PAGES}: u64 = 16;

type RM = RestrictedMemory<DefMem>;
type VM = VirtualMemory<RM>;

thread_local! {
  static ◊b{METADATA}: RefCell<◊code-ref["#stable-cell"]{StableCell}<Cbor<Option<Metadata>>, RM>> =
    RefCell::new(StableCell::init(
        RM::new(DefMem::default(), 0..METADATA_PAGES),
        Cbor::default(),
      ).expect("failed to initialize the metadata cell")
    );

  static ◊b{MEMORY_MANAGER}: RefCell<MM<RM>> = RefCell::new(
    MM::init(RM::new(DefMem::default(), METADATA_PAGES..u64::MAX))
  );

  static ◊b{BALANCES}: RefCell<◊code-ref["#stable-btree"]{StableBTreeMap}<Account, Amount, VM>> =
    MEMORY_MANAGER.with(|mm| {
      RefCell::new(StableBTreeMap::init(mm.borrow().get(◊b{BALANCES_MEM_ID})))
    });

  static ◊b{TX_LOG}: RefCell<◊code-ref["#stable-log"]{StableLog}<Cbor<Tx>, VM, VM>> =
    MEMORY_MANAGER.with(|mm| {
      RefCell::new(StableLog::init(
        mm.borrow().get(◊b{LOG_INDX_MEM_ID}),
        mm.borrow().get(◊b{LOG_DATA_MEM_ID}),
      ).expect("failed to initialize the tx log"))
    });
}
}
}

◊p{
  We are all set to start working on the ledger!
  I left implementing the rest of the specification as an exercise for an attentive reader.
}


◊section{
◊section-title["next"]{Where to go next}
◊ul[#:class "arrows"]{
  ◊li{Take a look at the library ◊a[#:href "https://github.com/dfinity/stable-structures/tree/main/examples/src"]{usage examples}.}
  ◊li{Check out real-world usage examples in production-quality canisters◊sidenote["sn-outdated"]{
    Note that these examples can use a slightly outdated library version.
  }, such as ◊a[#:href "https://github.com/dfinity/internet-identity/blob/97e8d968aba653c8857537ecd541b35de5085608/src/archive/src/main.rs"]{II archive} and ◊a[#:href "https://github.com/dfinity/ic/blob/df57b720fd0ceed70f021f4812c797fb40d97503/rs/bitcoin/ckbtc/minter/src/storage.rs"]{ckBTC minter}.}
}
}