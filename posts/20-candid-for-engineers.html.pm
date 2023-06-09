#lang pollen

◊(define-meta title "Candid for engineers")
◊(define-meta keywords "ic")
◊(define-meta summary "A practical guide to the world's most advanced interface definition language.")
◊(define-meta doc-publish-date "2023-06-20")
◊(define-meta doc-updated-date "2023-06-20")

◊section{
◊section-title["introduction"]{Introduction}
◊p{
  ◊a[#:href "https://github.com/dfinity/candid"]{Candid} is the primary interface definition language for smart contracts hosted on the ◊a[#:href "https://internetcomputer.org/"]{Internet Computer} (IC).
}

◊p{
  Most prevalent data-interchange formats, such as ◊a[#:href "https://protobuf.dev/"]{Protocol Buffers} and ◊a[#:href "https://thrift.apache.org/"]{Thrift}, come straight from ◊a[#:href "https://reasonablypolymorphic.com/blog/protos-are-wrong/#ad-hoc-and-built-by-amateurs"]{engineering departments}.
  Candid is different.
  Candid is a child of programming language designers who grew it from ◊a[#:href "https://github.com/dfinity/candid/blob/master/spec/Candid.md#design-goals"]{first principles}.
  As a result, Candid ◊a[#:href "https://github.com/dfinity/candid/blob/master/spec/IDL-Soundness.md"]{makes sense}, but might feel alien to most engineers.
}

◊p{
  This article is an introduction to Candid I wish I had when I started using it.
}
}

◊section{
◊section-title["candid-overview"]{Candid overview}

◊p{
  As any interface definition language, Candid has multiple facets.
}

◊p{
  One facet is the textual format defining service interface.
  This facet is similar in function to the ◊a[#:href "https://grpc.io/"]{gRPC} system.
  Another facet is the binary format for encoding service requests and responses.
  This facet is similar in function to the ◊a[#:href "https://protobuf.dev/"]{Protocol Buffers} serialization format.
}

◊p{
  Though Candid is similar to gRPC on the surface, there is an important distinction between the two systems.
}

◊p{
  gRPC builds strictly on top of the Protocol Buffers format.
  Service method definitions can refer to message definitions but messages cannot refer to services.
}

◊p{
  Candid, on the other hand, ties binary format and service definition language into a knot.
  Service method definitions can refer to data types, and data types can refer to services.
  Services can accept as arguments and return references to other services and methods.
  The Candid team usually call such designs ◊quoted{higher-order cases}.
  The ◊a[#:href "https://internetcomputer.org/docs/current/developer-docs/backend/candid/candid-concepts"]{Candid overview} article introduces a higher-order function in its first example.
}
◊figure{
◊source-code["candid"]{
service counter : {
  ◊em{// A method taking a reference to a function.}
  subscribe : (func (int) -> ()) -> ();
}
}
}

◊subsection-title["service-definitions"]{Service definitions}
◊p{
  Most often developers interact with Candid through the service definition files, also known as ◊code-ref["https://internetcomputer.org/docs/current/developer-docs/backend/candid/candid-howto#the-did-file"]{.did} files.
}

◊p{
  A ◊code{.did} file contains type definitions and at most one main service definition, which must be the last clause in the ◊code{.did} file.
}

◊figure{
◊marginnote["mn-token-interface"]{
The definition of a token ledger registry service.
The ◊code{service} keyword at the top level defines the main service; it must appear as the last definition in the file.
Note the difference between a service type definition (top) and a service definition (bottom) syntactic forms.
}
◊source-code["candid"]{
// A type definition introducing the Token service interface.
◊b{type} Token = ◊b{service} {
  token_symbol : () -> (text) query;
  balance : (record { of : principal }) -> (nat) query;
  transfer : (record { to : principal; amount : nat }) -> ();
};

◊b{service} TokenRegistry : {
  ◊em{// Returns a reference to a token ledger service given the token symbol.}
  lookup : (symbol : text) -> (opt Token) query;
}
}
}

◊p{
  There are two syntactic forms introducing a service definitions: with and without init arguments.
  The technical term for a service defition with init arguments is ◊a[#:href "https://docs.rs/candid/0.8.4/candid/types/internal/enum.Type.html#variant.Class"]{class}.
}

◊figure{
◊marginnote["mn-service-vs-class"]{
  Service definitions with (top) and without (bottom) init arguments (rendered in bold font).
}
◊source-code["candid"]{
◊b{service} Token : {
  balance : (record { of : principal }) -> (nat) query;
  ◊em{// ...}
}
}

◊source-code["candid"]{
◊b{service} Token : ◊b{(init_balances : vec record { principal; nat })} -> {
  balance : (record { of : principal }) -> (nat) query;
  ◊em{// ...}
}
}
}

◊p{
  Init arguments describe the value that the canister maintainers must specify when they instantiate the canister.
  Service clients don't need to worry about these arguments.
  Consequently, init arguments are not part of the public interface, so most tools ignore them (◊code-ref["https://internetcomputer.org/docs/current/references/cli-reference/dfx-canister#dfx-canister-install"]{dfx canister install} is a notable exception).
}

◊subsection-title["types"]{Types}

◊p{
  In additional to a rich set of pritivite types, such as booleans (◊code{bool}), floats (◊code{float64}), strings (◊code{text}), and whole numbers of various widths (◊code{nat8}, ◊code{nat16}, ◊code{nat32}, ◊code{nat64}, ◊code{int8}, ◊code{int16}, ◊code{int32}, ◊code{int64}), Candid provides a more advanced types and type constructors:
}

◊ul[#:class "arrows"]{
  ◊li{
    Arbitrary-precision integers (◊code-ref["https://internetcomputer.org/docs/current/references/candid-ref#type-nat"]{nat} and ◊code-ref["https://internetcomputer.org/docs/current/references/candid-ref#type-int"]{int}).
  }
  ◊li{
    Unique identifiers (◊code-ref["https://internetcomputer.org/docs/current/references/candid-ref#type-principal"]{principal}).
  }
  ◊li{
    The ◊code-ref["https://internetcomputer.org/docs/current/references/candid-ref#type-opt-t"]{opt} type constructor for marking values as potentially missing.
  }
  ◊li{
    The ◊code-ref["https://internetcomputer.org/docs/current/references/candid-ref#type-vec-t"]{vec} type constructor for declaring collections.
  }
  ◊li{
    ◊a[#:href "https://internetcomputer.org/docs/current/references/candid-ref#type-record--n--t--"]{Records} as product types with named fields (also known as ◊code{structs}), such as ◊br{}
    ◊code{◊b{record} { ◊em{first_line} : text; ◊em{second_line} : ◊b{opt} text; ◊em{zip} : text; /* ◊ellipsis{} */ }}.◊br{}
  }
  ◊li{
    ◊a[#:href "https://internetcomputer.org/docs/current/references/candid-ref#type-variant--n--t--"]{Variants} as sum types with named alternatives (also known as ◊code{enums}), such as ◊br{}
    ◊code{◊b{variant} { ◊em{cash}; ◊em{credit_card} : ◊b{record} { /* ◊ellipsis{} */ } }}.◊br{}
  }
  ◊li{
    The ◊code-ref["https://internetcomputer.org/docs/current/references/candid-ref#type-reserved"]{reserved} type for retiring unused fields.
  }
  ◊li{
    The ◊code-ref["https://internetcomputer.org/docs/current/references/candid-ref#type-func---"]{func} type family describing actor method signatures.
    Values of such types represent references to actor methods (actor address + method) of the corresponding type.
  }
  ◊li{
    The ◊code-ref["https://internetcomputer.org/docs/current/references/candid-ref#type-service-"]{service} type family describing actor interfaces.
    It might be helpful to view service types as special kinds of records where all fields are functions.
    Values of service types represent references to actors providing the corresponding interface.
  }
}

◊subsection-title["records-and-variants"]{Records and variants}

◊subsection-title["structural-typing"]{Structural typing}

◊p{
  Candid's type system is ◊a[#:href "https://en.wikipedia.org/wiki/Structural_type_system"]{structural}: it treats types as equal if they have identical structure.
  Type names serve as monikers for the type structure, not as the type's identity.
}

◊p{
  Variable bindings in Rust are a good analogy for type names in Candid.
  The ◊code{let x = 5;} statement ◊em{binds} name ◊em{x} to value ◊code{5}, but ◊em{x} does not become an identity of that value.
  Expressions such as ◊code{x == 5} and ◊code{{ let y = 5; y == x }} evaluate to ◊code{true}.
}

◊figure{
◊marginnote["mn-structural-types"]{
  Candid views types ◊code{Point2d}, modeling a point on a plane, and ◊code{ECPoint}, modeling a point on an elliptic curve, as interchangeable because they have identical structure.
}

◊source-code["candid"]{
◊em{// These types are identical from Candid's point of view.}
type Point2d = record { x : int; y : int };
type ECPoint = record { x : int; y : int };
}
}

◊p{
  Usually, you don't have to name types, you can instead inline them in service definitions (unless you define recursive types, of course).
  Assigning descriptive names can improve the interface readability, however.
}

◊figure{
◊marginnote["mn-type-names"]{
  Candid allows you to omit types names for non-recursive type definitions.
  Service types ◊code{S1} and ◊code{S2} are interchangeable.
}

◊source-code["candid"]{
type ◊b{S1} = service {
  store_profile : (nat, record { name : text; age : nat }) -> ();
};

type UserProfile = record { name : text; age : nat };
type UserId = nat;

type ◊b{S2} = service {
  store_profile : (UserId, UserProfile) -> ();
};
}
}

◊subsection-title["binary-message-anatomy"]{Binary message anatomy}
◊p{
  A binary Candid message defines a tuple of ◊math{n} values and logically consists of three parts:
}
◊ol-circled{
  ◊li{
    ◊em{Type table} defines custom types (◊a[#:href "https://internetcomputer.org/docs/current/references/candid-ref#type-record--n--t--"]{records}, ◊a[#:href "https://internetcomputer.org/docs/current/references/candid-ref#type-variant--n--t--"]{variants}, ◊a[#:href "https://internetcomputer.org/docs/current/references/candid-ref#type-opt-t"]{options}, ◊a[#:href "https://internetcomputer.org/docs/current/references/candid-ref#type-vec-t"]{vectors}, etc.) required to decode the message.
  }
  ◊li{
    ◊em{Types} is an ◊math{n}-tuple of integers specifying the types ◊math{(T◊sub{1},◊ellipsis{},T◊sub{n})} of values in the next section.
    The types are either primitives (negative integers) or pointers into the type table (non-negative integers).
  }
  ◊li{
    ◊em{Values} is an ◊math{n}-tuple of serialized values ◊math{(V◊sub{1},◊ellipsis{},V◊sub{n})}.
  }
}


◊subsection-title["encoding-a-tree"]{Example: encoding a tree}

◊p{
  Let's look at an example of a type table corresponding to a ◊a[#:href "https://en.wikipedia.org/wiki/Rose_tree"]{rose tree}.
}

◊figure{

◊marginnote["mn-rose-tree"]{
  A definition of a ◊a[#:href "https://en.wikipedia.org/wiki/Rose_tree"]{rose tree} data type containing 32-bit integers (top) and the Candid representation of the same type (bottom).
}

◊source-code["rust"]{
◊em{// Rust}
pub enum Tree { Leaf(i32), Forest(Vec<Tree>) }
}
◊source-code["candid"]{
◊em{// Candid}
type Tree = variant { leaf : int32; forest : vec Tree };
}
}

◊p{
  Let's represent the ◊code{Tree} type using at most one composite type per type definition.
  This ◊quoted{canonical} form will help us understand the message type table.
}

◊figure{

◊marginnote["mn-rose-tree-canonical"]{
  The canonical representation of the ◊code{Tree} type.
}

◊source-code["candid"]{
type T0 = variant { leaf : int32; forest : T1 };
type T1 = vec T0;
}
}

◊p{
  Let's encode a fork with two children equivalent to ◊code{Tree::Forest(vec![Tree::Leaf(1), Tree::Leaf(2)])} Rust expression using the ◊a[#:href "https://github.com/dfinity/candid/tree/f7166f47d895e411a74de1eba4b347ac75f5fd26/tools/didc"]{didc} tool.
}

◊figure{
◊marginnote["mn-encode-command"]{
  The shell commands to encode a tree using the ◊code{didc} tool.
  The ◊code{--defs} option loads type definitions from a file; the ◊code{--types} option specifies the types of values in the tuple (see point ◊circle-ref[2] in the ◊a[#:href "binary-message-anatomy"]{binary message anatomy} section.
}
◊source-code["shell"]{
$ echo 'type Tree = variant { leaf : int32; forest : vec Tree };' > tree.did
$ didc encode \
       --defs   tree.did \
       --types  '(Tree)' \
       '(variant { forest = vec { variant { leaf = 1 }; variant { leaf = 2 } } })'
4449444c026b029e87c0bd0475dd99a2ec0f016d000100010200010000000002000000
}
}

◊p{
  Let's look closely at the bytes.
}

◊figure{
◊source-code["ascii"]{
           ⎡ 44 ⎤ D
    Magic  ⎢ 49 ⎥ I
           ⎢ 44 ⎥ D
           ⎣ 4c ⎦ L

           ⎡ 02 ] number of table entries (2)
           ⎢ 6b ] entry #0: variant type
           ⎢ 02 ] number of fields (2)
           ⎢ 9e ⎤
           ⎢ 87 ⎥
           ⎢ c0 ⎥ field name ("leaf") hash
           ⎢ bd ⎥
           ⎢ 04 ⎦
Type table ⎢ 75 ] field #0 type: int32
           ⎢ dd ⎤
           ⎢ 99 ⎥
           ⎢ a2 ⎥ field name ("forest") hash
           ⎢ ec ⎥
           ⎢ 0f ⎦
           ⎢ 01 ] field #1 type: see entry #1
           ⎢ 6d ] entry #1: vec type         
           ⎣ 00 ] vec item type: entry #0

    Types  ⎡ 01 ] number of tuple elements (1)
           ⎣ 00 ] type of the first element (entry #0)

           ⎡ 01 ] value #0: variant field #1 ("forest")
           ⎢ 02 ] number of elemens in the vector
           ⎢ 00 ] variant field #0 ("leaf")
           ⎢ 01 ⎤
           ⎢ 00 ⎥ 1 : int32 (little-endian)
    Values ⎢ 00 ⎥
           ⎢ 00 ⎦
           ⎢ 00 ] variant field #0 ("leaf")
           ⎢ 02 ⎤
           ⎢ 00 ⎥ 2 : int32 (little-endian)
           ⎢ 00 ⎥
           ⎣ 00 ⎦
}
}

◊p{
  Note that the type table does not contain record field or variant alternative names.
}

◊subsection-title["subtyping"]{Subtyping}

◊p{
  One of Candid's distinctive traits is the use of structural ◊a[#:href "https://en.wikipedia.org/wiki/Subtyping"]{subtyping} for defining backward-compatible interface evolutions◊sidenote["sn-upgradable"]{
    The Candid spec calls such evolutions ◊a[#:href "https://github.com/dfinity/candid/blob/master/spec/Candid.md#upgrading-and-subtyping"]{type upgrades}.
  }.
  If a type ◊math{T} is a subtype of type ◊math{V} (denoted ◊math{T <: V}), then Candid can decode any value of type ◊math{T} into a value of type ◊math{V}.
}

◊p{
  Let's inspect some of the basic subtyping rules for simple values (not functions):
}

◊ul[#:class "arrows"]{
  ◊li{
    Subtyping is ◊a[#:href "https://en.wikipedia.org/wiki/Reflexive_relation"]{reflexive}: any type is a subtype of itself.
    If you don't change the interface, you don't break the clients.
  }
  ◊li{
    Subtyping is ◊a[#:href "https://en.wikipedia.org/wiki/Transitive_relation"]{transitive}: ◊math{T <: V} and ◊math{V <: W} implies ◊math{T <: W}.
    A sequence of backward-compatible changes is backward-compatible as a whole.
  }
  ◊li{
    Adding a new field to a record creates a subtype.◊br{}
    ◊code{record { name : text; status : variant { user; admin } } <: record { name : text } }
  }
  ◊li{
    Less intuitively, removing an ◊em{optional} field also creates a subtype.
    ◊br{}
    ◊code{record { name : text } <: record { name : text; status : ◊b{opt} variant { user; admin } } }
  }
  ◊li{
    Removing a case in a variant creates a subtype.◊br{}
    ◊code{variant { yes; no } <: variant { yes; no; unknown }}
  }
  ◊li{
    All types are subtypes of the ◊code{reserved} type.
    Candid can happily decode any type into a reserved field.
  }
}

◊p{
  Function subtyping follows the common ◊a[#:href "https://en.wikipedia.org/wiki/Covariance_and_contravariance_(computer_science)#Function_types"]{variance rules}:
  function ◊code{g : C -> D} is a subtype of function ◊code{f : A -> B} if ◊code{A <: C} and ◊code{D <: B}.
  Informally, ◊code{g} must accept the same or more generic arguments as ◊code{f} and produce the same or more specific results as ◊code{f}.
}

◊p{
  Understanding the subtyping rules for functions is helpful for reasoning about safe interface migrations.
  Let's consider a few examples of common changes that preserve backward compatibility of a function interface (note that compatibility rules for arguments and results are often reversed).
}

◊ul[#:class "arrows"]{
  ◊li{
    Remove an unused record field (or, better, change its type to ◊code{reserved}) from the method ◊em{input} argument.
  }
  ◊li{
    Add a new case to a variant in the method ◊em{input} argument.
  }
  ◊li{
    Add a new field to the method ◊em{result} type.
  }
  ◊li{
    Remove an optional field from the method ◊em{result} type.
  }
  ◊li{
    Remove a case from the variant type in the method ◊em{result} type.
  }
}

◊p{
  The rules mentioned in this section are by no means complete or precise; please refer to the ◊a[#:href "https://github.com/dfinity/candid/blob/master/spec/Candid.md#rules"]{typing rules} section of the Candid specification for a formal definition.
  Before we close the subtyping discussion, however, let's consider the following type evolution.
}

◊figure{
◊marginnote["mn-subtype-opt"]{
  An example of the ◊em{special opt subtyping rule}.
  Step ◊circled-ref[1] removes the optional ◊code{status} field, step ◊circled-ref[2] adds an optional field with the same name but incompatible type.
  The horizontal bar applies the transitive property of subtyping, eliminating the intermediate type without the ◊code{status} field.
}
◊source-code["candid"]{
   record { name : text; status : opt variant { user;   admin   } }
<: record { name : text } ◊circled-ref[1]
<: record { name : text; status : opt variant { single; married } } ◊circled-ref[2]
◊hr{}   record { name : text; status : opt variant { user;   admin   } }
<: record { name : text; status : opt variant { single; married } }
}
}

◊p{
  Indeed, ◊math{opt T <: V} holds for any types ◊math{T} and ◊math{V} in Candid.
  This counter-intuitive property bears the name of ◊em{special opt rule}◊sidenote["sn-opt-is-special"]{Joachim Breitner's ◊a[#:href "https://www.joachim-breitner.de/blog/784-A_Candid_explainer__Opt_is_special"]{opt is special} article explores the topic in more detail and provides historical background.}, and it causes a lot of grief in practice.
  Multiple developers reported changing an optional field in an incompatible way, causing the corresponding values to decode as ◊code{null} after the upgrade.
}

}

◊section{
◊section-title["faq"]{FAQ}

◊subsection-title["faq-remove-field"]{Can I remove a record field?}

◊p{
  Short answer: Sometimes you can, but please don't.
}

◊p{
  It's always safe to remove an ◊code{opt} field, but prefer marking it ◊code{reserved} instead.
  Reserved fields make it unlikely that future service developers will use the field name in an incompatible way.
}

◊source-code["good"]{
◊em{// OK: the age field is optional.}
 type User = record {
   name : text;
-  age : opt nat;
 };

 service UserService : {
  add_user : (User) -> (nat);
  get_user : (nat) -> (User) query;
 }
}

◊source-code["good"]{
◊em{// GOOD: marking an opt field as reserved.}
 type User = record {
   name : text;
-  age : opt nat;
-  age : ◊b{reserved};
 };

 service UserService : {
  add_user : (User) -> (nat);
  get_user : (nat) -> (User) query;
 }
}

◊p{
  The answer depends on the record type variance if the field is not ◊code{opt}.
}

◊p{
  You can remove the field if the type appears only in method arguments, but prefer marking it ◊code{reserved} instead.
}

◊source-code["good"]{
 service UserService : {
-  add_user : (record { name : text;  age : nat }) -> (nat);
+  add_user : (record { name : text             }) -> (nat);
 }
}

◊source-code["good"]{
 service UserService : {
-  add_user : (record { name : text; age : nat      }) -> (nat);
+  add_user : (record { name : text; ◊b{age : reserved} }) -> (nat);
 }
}

◊p{
   You will have to preserve the field if the type appears in a method return type.
}

◊source-code["bad"]{
◊em{// BAD: the User type appears as an argument ◊b{and} a result.}
 type User = record {
   name : text;
-  age : nat;
};

 service UserService : {
  add_user : (User) -> (nat);
  get_user : (nat) -> (User) query;
 }
}

◊subsection-title["faq-remove-field"]{Can I add a record field?}

◊p{
  Adding an ◊code{opt} field is always safe.
}

◊source-code["good"]{
 type User = record {
   name : text;
+  age : opt nat;
};

 service UserService : {
  add_user : (User) -> (nat);
  get_user : (nat) -> (User) query;
 }
}

◊p{
  For non-◊code{opt} fields, the answer depends on the type variance.
}

◊p{
  You can safely add a non-optional field, if the record appears only in method return types.
}

◊source-code["good"]{
 ◊em{// BAD: breaks the client code}
 service UserService : {
-  get_user : (nat) -> (record { name : text            }) query;
+  get_user : (nat) -> (record { name : text; ◊b{age : nat} }) query;
 }
}

◊p{
  If the record appears in a method argument, adding a non-optional field breaks backward compatibility.
}

◊source-code["bad"]{
 service UserService : {
-  add_user : (record { name : text            }) -> (nat);
+  add_user : (record { name : text; ◊b{age : nat} }) -> (nat);
 }
}


◊subsection-title["faq-remove-alternative"]{Can I remove a variant alternative?}

◊p{
  It depends on the type variance.
}

◊p{
  You can remove alternatives if the variant appears only in method results.
}

◊source-code["good"]{
 service CoffeeShop : {
-  order_size : (nat) -> (variant { tiny; small; medium; large }) query;
+  order_size : (nat) -> (variant {       small; medium; large }) query;
 }
}

◊source-code["bad"]{
 ◊em{// BAD: this change might break clients.}
 service CoffeeShop : {
-  order_coffee : (record { size : variant { tiny; small; medium; large } }) -> (nat);
+  order_coffee : (record { size : variant {       small; medium; large } }) -> (nat);
 }
}


◊subsection-title["faq-remove-alternative"]{Can I add a variant alternative?}

◊p{
  It depends on the type variance.
}

◊p{
  You can safely add new alternatives, if the variant appears only in method arguments.
}

◊source-code["good"]{
 service UserService : {
-  add_user : (record { name : text;  age : variant { child;           adult }}) -> (nat);
+  add_user : (record { name : text;  age : variant { child; ◊b{teenager}; adult }}) -> (nat);
 }
}

◊source-code["bad"]{
◊em{// BAD: the User type appears as an argument ◊b{and} a result.}
 type User = record {
   name : text;
-  age : variant { child;           adult }
+  age : variant { child; ◊b{teenager;} adult }
};

 service UserService : {
  add_user : (User) -> (nat);
  get_user : (nat) -> (User) query;
 }
}

◊subsection-title["faq-change-init-args"]{Can I change init args?}
◊p{
  Short answer: yes.
}

◊p{
  Service init args are not part of the public interface.
  Only service maintainers need to encode the init args; service clients don't need to worry about them.
  Service interface compatibility tools, such as ◊code-ref["https://github.com/dfinity/candid/blob/e212e096cb726548c6d6edba1189375dc5ad364e/tools/didc/README.md"]{didc check}, ignore init args.
}

◊subsection-title["faq-post-upgrade-arg"]{How do I specify the post_upgrade arg?}

◊p{
  As of June 2023, Candid service definition language does not support specifying ◊code{post_upgrade} arguments.
}

◊p{
  However, there exists a workaround.
  Most canister management tools use the same type definition for encoding the init args and upgrade args.
  You can define a variant type to distinguish between these.
}

◊figure{
◊marginnote["mn-post-upgrade-type"]{
  Using a variant type for differentiating between service init and upgrade arguments.
}

◊source-code["candid"]{
◊b{type} ServiceArg = variant {
  Init    : record { minter : principal };
  ◊em{// We might want to override the minter on upgrade.}
  Upgrade : record { minter : ◊b{opt} principal }
};

◊b{service} TokenService : (ServiceArg) -> {
  ◊em{// ◊ellipsis{}}
}
}
}

}

◊section{
◊section-title["excercises"]{Excercises}
}

◊section{
◊section-title["resources"]{Resources}
◊ul[#:class "arrows"]{
  ◊li{
    Joachim Breitner's ◊a[#:href "https://www.joachim-breitner.de/blog/782-A_Candid_explainer__The_rough_idea"]{Candid explainer} (the ◊a[#:href "https://www.joachim-breitner.de/blog/786-A_Candid_explainer__Quirks"]{Quirks} part is especially relevant for engineers).
  }
  ◊li{
    ◊a[#:href "https://internetcomputer.org/docs/current/developer-docs/build/candid/candid-intro/"]{Candid for developers}
  }
  ◊li{
    ◊a[#:href "https://fxa77-fiaaa-aaaae-aaana-cai.raw.ic0.app/explain"]{Ben Lynn's Candid explainer}
  }
  ◊li{
    ◊a[#:href "https://github.com/dfinity/candid/blob/master/spec/Candid.md"]{The Candid Specification}
  }
}
}
