#lang pollen

◊(define-meta title "Square joy: trapped rainwater")
◊(define-meta keywords "j,arrays,puzzles")
◊(define-meta summary "Solving the trapped rain water problem in J.")
◊(define-meta doc-publish-date "2022-02-15")
◊(define-meta doc-updated-date "2022-02-15")

◊section{
◊p{
  In this article, we will explore one of my favorite programming puzzles using the ◊a[#:href "https://en.wikipedia.org/wiki/Array_programming"]{array programming} paradigm.
}
}

◊section{
◊section-title["the-why"]{But why?}

◊p{
  I am always looking for new perspectives on software engineering and programming.
  My views on computing changed profoundly when I discovered the array programming paradigm a few years ago.
}

◊p{
  For me, the hardest and the most rewarding part of array programming is coming up with simple idiomatic solutions.
  This requires knowledge of many little tricks that array-wrangling wizards developed in their chambers over the last 50 years.
  I would love to learn or rediscover these tricks, and I hope you might derive some pleasure and insights from reading about my little discoveries.
}

◊p{
  In this article, we will use the ◊a[#:href "https://www.jsoftware.com/#/"]{J programming language}.
  Why J and not, say, ◊a[#:href "https://dyalog.com/"]{APL}?
  APL is a great language as well, but I have trouble running it on my machine.
  J is also much easier to type on most keyboards, and it is ◊a[#:href "https://github.com/jsoftware/jsource"]{open source}.
}

◊p{
  If you are not familiar with J, it will look like line noise to you.
  I will explain most of the steps that we make, but it might still look like black magic at times.
  That is normal when you are working with J.
  My goal is not to explain every aspect of the language, but rather demonstrate the approach to problem solving.
}
◊p{
  Time to have some fun!
}
}

◊section{
◊section-title["the-problem"]{The problem: heavy rains in Flatland}

◊p{
  Imagine that we live in a two-dimensional city, where all buildings have the same unit width and stand next to one another.
  We do not like rains very much: the two-dimensional water gets stuck between the buildings forever, forming pools.
  As the city architects, we know the heights in units of all the buildings.
  We need to compute how much water (in square units) gets accumulated between the buildings after heavy rain.
}

◊p{
  More dryly: given an array of non-negative integers ◊em{H}, representing heights of unit-width bars placed next to one another, compute the total area of water trapped by the configuration after it rains.
}

◊subsection-title["example-2d"]{Example}
◊dl{
◊dt{Input} ◊dd{◊pre{0 1 0 2 1 0 1 3 2 1 2 1}}
◊dt{Output} ◊dd{◊pre{6}}
}
◊figure{
 ◊marginnote{The configuration of bars with heights 0, 1, 0, 2, 1, 0, 1, 3, 2, 1, 2, 1, and the water trapped by this configuration.}
 ◊p{
   ◊img[#:src "/images/04-viewmat-2d.png" #:alt "a picture of the example"]
 }
}
}

◊section{
◊section-title["a-solution"]{A solution}
◊p{
 A natural question to ask is what is the water level above each bar?
 If we knew that, summing contributions of levels above each bar would give us the answer.
}
◊p{
 So let us focus on a bar at an arbitrary index ◊em{i}.
 What would stop the water from flowing out?
 A bar that is higher than ◊em{H[i]}.
 Furthermore, we need bars higher than ◊em{H[i]} on ◊em{both} sides of ◊em{i} for the water to stay.
 So the level of water at index ◊em{i} is determined by the minimum of the highest bars on the left and on the right.
}

◊p{
 Computing the highest bar to the left and to the right for each index is not efficient: we would need to make ◊em{O(N◊sup{2})} steps.
 Luckily, there is a lot of duplication in this computation that we can eliminate.
 Instead of running the search from each position in the array, we can precompute left and right maxima all positions in two sweeps.
}
◊p{
 The algorithm to compute the running left maximum is called ◊a[#:href "https://en.wikipedia.org/wiki/Prefix_sum"]{prefix scan}.
 We can compute the right maximum by running the same scan from right to left (i.e., performing a suffix scan).
 Taking the minimum of precomputed left and right maxima gives us the water level at each point.
 The difference between the water level and the bar height gives us the amount of water trapped at this position.
 Summing up these amounts gives us the answer.
}
}

◊section{
◊section-title["translating-to-j"]{Translating our idea to J}

◊p{
  J is an interpreted language and it has a ◊a[#:href "https://en.wikipedia.org/wiki/Read%E2%80%93eval%E2%80%93print_loop"]{REPL}.
  It is quite common for J programmers to build solutions incrementally by trying snippets of code in the REPL and observing the effects.
  The code in this article is also an interactive REPL session that you can replicate locally.
  Let us get some data to play with.
}

◊source-code["j"]{
    NB. Comments start with the symbol NB.
    NB. I will use PascalCase for data ("nouns")
    NB. and snake_case for functions ("verbs").

    NB. User input is indented.
NB. Machine output is not.

    H =. 0 1 0 2 1 0 1 3 2 1 2 1
}

◊p{
  The next item on our agenda is computing the left and right running maxima.
}

◊source-code["j"]{
    ◊b{>./\} H
0 1 1 2 2 2 2 3 3 3 3 3

    ◊b{>./\.} H
3 3 3 3 3 3 3 3 2 2 2 1
}

◊p{
  Wait, where is all the code?
  Let me break it down.
  In J, ◊a[#:href "https://code.jsoftware.com/wiki/Vocabulary/gtdot#dyadic"]{◊code{>.} (max)} is a verb (J word for "function") that, when you use it dyadically (J word for "with two arguments"), computes the maximum of the arguments.
  It is easy to guess that ◊a[#:href "https://code.jsoftware.com/wiki/Vocabulary/ltdot#dyadic"]{◊code{<.} (min)} is an analogous verb that computes the minimum.
}

◊p{
  The single character ◊a[#:href "https://code.jsoftware.com/wiki/Vocabulary/slash"]{◊code{/} (insert)} is an adverb (J word for "function modifier") that takes a dyadic verb to the left and turns it into a verb that folds an entire array.
  Why is it called "insert"?
  Because it inserts the verb between elements of the array it operates on.
  For example, summing up an array is just ◊code{+/}.
}

◊source-code["j"]{
    NB. +◊b{/} 1 2 3 4    <->    1 + 2 + 3 + 4

    +◊b{/} 1 2 3 4
10
}

◊p{
  But wait, we want running results, not just the final maximum.
  That is a job for adverbs ◊a[#:href "https://code.jsoftware.com/wiki/Vocabulary/bslash"]{◊code{\} (prefix)} and ◊a[#:href "https://code.jsoftware.com/wiki/Vocabulary/bslashdot"]{◊code{\.} (suffix)}.
  These take a verb and produce a new verb that applies the original verb to all prefixes/suffixes of an array, forming a new array.
}

◊source-code["j"]{
    NB. +/\  1 2 3 4    <->    (1) (+/ 1 2) (+/ 1 2 3) (+/ 1 2 3 4)
    NB. +/\. 1 2 3 4    <->    (+/ 1 2 3 4) (+/ 2 3 4) (+/ 3 4) (4)

    +/◊b{\} 1 2 3 4
1 3 6 10

    +/◊b{\.} 1 2 3 4
10 9 7 4
}

◊p{
  We already know enough to compute water levels for our example:
}

◊source-code["j"]{
    (>./\ H) ◊b{<.} (>./\. H)
0 1 1 2 2 2 2 3 2 2 2 1
}

◊p{
  Now we need to subtract the bar heights and sum up the results.
  We can get away with tools that we already know:
}

◊source-code["j"]{
    NB. Look at the picture in the example and convince yourself that the
    NB. water amounts we computed are correct.

    ((>./\ H) <. (>./\. H)) ◊b{- H}
0 0 1 0 1 2 1 0 0 1 0 0

    ◊b{+/} ((>./\ H) <. (>./\. H)) - H
6
}

◊p{
  This is a remarkably short solution.
  Believe it or not, we can make it even shorter.
  Look at the argument that we have to repeat three times, and at all these parentheses.
  If only we could move some of those out...
}

◊source-code["j"]{
    +/@((>./\ <. >./\.) - ]) H
6
}

◊p{
  Such terse expressions that combine functions without mentioning their arguments are called ◊a[#:href "https://www.jsoftware.com/help/jforc/tacit_programs.htm"]{tacit}.
  I will not explain here how to form these expressions, but I encourage you to learn more about it on your own.
}

◊p{
  Let us bind our beautiful tacit expression to a name.
}

◊source-code["j"]{
    trapped =. +/@((>./\ <. >./\.)-])
    trapped 0 1 0 2 1 0 1 3 2 1 2 1
6
}

◊p{
  The full implementation of our idea now fits into 12 ASCII characters.
  One of the interesting properties of array languages is that often it is not worth it to name functions.
  Their full body is shorter and more expressive than any name you can come up with.
}
}

◊section{
◊section-title["drawing-solutions"]{Drawing solutions}

◊p{
  Knowing the answer is great, but being able to ◊em{see} it at a glance would be even better.
  In this section, we will write some code to represent our solutions visually.
}

◊p{
  What would we like to see in that picture?
  We want to tell the space from the buildings, and from the water pools.
}

◊p{
  Let us start by drawing the original problem first.
  We know how to compute maxima, that is just ◊code{>./ H}.
  Now we need to build a matrix ◊em{max(H)} rows by ◊em{length(H)} columns.
  The idiomatic way of doing this is using our old friend ◊a[#:href "https://code.jsoftware.com/wiki/Vocabulary/slash#dyadic"]{◊code{/} (table)} in a new disguise. 
  When used as ◊code{noun1 verb/ noun1}, slash builds a ◊em{length(noun1)} by ◊em{length(noun2)} table, where each cell ◊em{i, j} is filled with the value computed as ◊em{noun1[i] verb noun2[j]}.
}

◊p{
  Let us make a multiplication table to get some feel of how it works.
  We will also need ◊a[#:href "https://code.jsoftware.com/wiki/Vocabulary/idot"]{◊code{i.} (integers)}, the function that takes an integer and makes an arithmetic progression of that length starting at zero.
}

◊source-code["j"]{
    i. 10
0 1 2 3 4 5 6 7 8 9

    NB. When the input is negative, the progression is descending.
    i. _10
9 8 7 6 5 4 3 2 1 0

    (i. 10) */ (i. 10)
0 0  0  0  0  0  0  0  0  0
0 1  2  3  4  5  6  7  8  9
0 2  4  6  8 10 12 14 16 18
0 3  6  9 12 15 18 21 24 27
0 4  8 12 16 20 24 28 32 36
0 5 10 15 20 25 30 35 40 45
0 6 12 18 24 30 36 42 48 54
0 7 14 21 28 35 42 49 56 63
0 8 16 24 32 40 48 56 64 72
0 9 18 27 36 45 54 63 72 81
}

◊p{
  Note that there is no special boolean type in array languages.
  They use integers instead: false is zero and true is one.
}

◊source-code["j"]{
    NB. Here we build a table of using the verb "less" (<).
    (i. 5) </ (i. 5)
0 1 1 1 1
0 0 1 1 1
0 0 0 1 1
0 0 0 0 1
0 0 0 0 0
}

◊p{
  We have all the tools we need to display our problems and solutions.
}

◊source-code["j"]{
    NB. Compute the maximum of H.
    >./ H
3

    NB. Negate the maximum of H.
    - >./ H
_3

    NB. Make a descending progression that has the length of H maximum.
    i. - >./ H
2 1 0

    NB. Make a "less" table from the progression above and H.
    (i. - >./ H) </ H
0 0 0 0 0 0 0 1 0 0 0 0
0 0 0 1 0 0 0 1 1 0 1 0
0 1 0 1 1 0 1 1 1 1 1 1
}

◊p{
  If you squint a bit, you will see in the pattern of zeros and ones above the configuration of bars corresponding to ◊em{H}.
  We already know how to compute water levels, let us add them (quite literally) to the picture.
}

◊source-code["j"]{
    NB. Make a similar "less" table, but use water levels instead of just H.
    (i. - >./ H) </ ((>./\ <. >./\.) H)
0 0 0 0 0 0 0 1 0 0 0 0
0 0 0 1 1 1 1 1 1 1 1 0
0 1 1 1 1 1 1 1 1 1 1 1

    NB. Add two "less" tables component-wise.
    ((i. - >./ H) </ ((>./\ <. >./\.) H)) + (i. - >./ H) </ H
0 0 0 0 0 0 0 2 0 0 0 0
0 0 0 2 1 1 1 2 2 1 2 0
0 2 1 2 2 1 2 2 2 2 2 2
}

◊p{
  Look carefully at the matrix that we got.
  Zeros correspond to empty spaces, ones — to water pools, twos — to bars.
}

◊p{
  Let us extract and name the verb that converts an instance of our problem into a matrix with classified cells.
  I will not explain how this tacit expression works, but I am sure you can see a lot of common parts with the expression above.
}

◊source-code["j"]{
    pic =. ((i.@-@:(>./) </ (>./\ <. >./\.)) + (i.@-@:(>./) </ ]))
    pic H
0 0 0 0 0 0 0 2 0 0 0 0
0 0 0 2 1 1 1 2 2 1 2 0
0 2 1 2 2 1 2 2 2 2 2 2
}

◊p{
  We are one step away from turning this matrix into a picture.
}

◊source-code["j"]{
    (pic H) ◊"{" ucp ' ░█'
       █    
   █░░░██░█ 
 █░██░██████
}

◊p{
◊code{ucp} is a built-in verb that constructs an array of Unicode codepoints from a UTF-8 encoded string.
◊a[#:href "https://code.jsoftware.com/wiki/Vocabulary/curlylf#dyadic"]{◊code{◊"{"} (from)} is at the heart of our drawing trick.
This verb selects items from the right argument according to the indices from the left argument.
The effect is that all zeros got replaced with a space, ones — with a watery-looking glyph, and twos — with a solid rectangle.
}

◊p{
  Our pseudo-graphics look quite impressive already, but we can do even better.
  J comes with a convenient ◊a[#:href "https://code.jsoftware.com/wiki/Studio/Viewmat"]{viewmat} library that can visualize arrays.
}

◊source-code["j"]{
    require 'viewmat'
    viewmat pic H
}

◊figure{
 ◊p{
   ◊img[#:src "/images/04-viewmat-2d-raw.png" #:alt "viewmat pic H"]
 }
}

◊p{
  That looks quite good already, but the colors are a bit too psychedelic for my taste.
  Let us use a more neutral color scheme.
}

◊source-code["j"]{
    (255 255 255 , 0 0 128 ,: 128 128 128) viewmat pic H
}

◊figure{
 ◊p{
   ◊img[#:src "/images/04-viewmat-2d.png" #:alt "viewmat pic H"]
 }
}

◊p{
  Ah, much better!
  Now you know how I got the picture for the example.
}

◊p{
  Alternatively, we can use the ◊a[#:href "https://code.jsoftware.com/wiki/Plot"]{plot} package and draw our solution as a stacked bar chart.
  However, this approach needs more configuration and is slightly more cumbersome to use than ◊code{viewmat}.
}

◊source-code["j"]{
    require 'plot'
    'sbar;color gray,blue;aspect 0.5;barwidth 1;edgesize 0;frame 0;labels 0 1' plot H ,:  ((>./\ <. >./\.)-]) H
}
◊figure{
 ◊p{
   ◊img[#:src "/images/04-plot-2d.png" #:alt "2D plot graph"]
 }
}
}

◊section{
◊section-title["3d"]{Breaking out of Flatland}
◊p{
  One of the ways to better understand a problem is to generalize it.
  Let us break out into the third dimension.
}

◊p{
  Given a ◊em{two-dimensional} array of non-negative integers ◊em{H}, representing heights of square-unit bars placed next to one another, compute the total ◊em{volume} of water trapped by the configuration after it rains.
}

◊p{
  To make the problem more concrete, let us make a few instances.
  We will use ◊a[#:href "https://code.jsoftware.com/wiki/Vocabulary/tilde"]{◊code{~} (reflex)} adverb to save us some typing.
  This adverb takes a verb and produces another verb that duplicates its right argument and passes the copies as the left and the right argument of the original verb.
}

◊source-code["j"]{
    NB. +/~ X   <->   X +/ X
    NB. A cone that traps no water.
    +/~  (i. 4) , (i._4)
0 1 2 3 3 2 1 0
1 2 3 4 4 3 2 1
2 3 4 5 5 4 3 2
3 4 5 6 6 5 4 3
3 4 5 6 6 5 4 3
2 3 4 5 5 4 3 2
1 2 3 4 4 3 2 1
0 1 2 3 3 2 1 0

    NB. An inversed code that traps water in the middle.
    +/~  (i. _4), (i. 4)
6 5 4 3 3 4 5 6
5 4 3 2 2 3 4 5
4 3 2 1 1 2 3 4
3 2 1 0 0 1 2 3
3 2 1 0 0 1 2 3
4 3 2 1 1 2 3 4
5 4 3 2 2 3 4 5
6 5 4 3 3 4 5 6
}

◊subsection-title["solution-3d"]{Solution}

◊p{
  Let us play the same trick: pick an arbitrary place on the grid and think of the water level we will observe at that place.
  This time the problem is a bit trickier because there are many more ways for the water to flow.
  We have to consider all possible paths through the grid.
  For each path, there is the highest bar that the water will have to flow through.
  The water will choose a path where that highest bar is the lowest among all paths.
  And the height of that bar will determine the water level at that position.
}

◊p{
  Running a graph search from each point is very inefficient.
  Luckily, we do not have to.
  All our searches have the same destination, the "ground" outside of the grid!
  We can invert the problem and ask: what is the most efficient way for the water to "climb up" the bars?
  In this formulation, a single run of a shortest-path algorithm will give us the answer.
}

◊p{
  What shortest path algorithm should we use?
  ◊a[#:href "https://en.wikipedia.org/wiki/Dijkstra%27s_algorithm"]{Dijkstra algorithm} is the best in class for this problem.
  However, it needs a priority queue to work well, and it uses a lot of branching.
  Let us search for a more array-friendly solution.
}

◊p{
  There is another approach to the shortest path problem, a beautifully simple ◊a[#:href "https://en.wikipedia.org/wiki/Bellman%E2%80%93Ford_algorithm"]{Bellman-Ford algorithm} that works by incremental relaxation of the distance matrix.
  It looks especially simple for implicitly defined graphs like our grid.
  Here is how to apply it to our problem:
}

◊ul[#:class "arrows"]{
  ◊li{
    Start with a grid of distances that has the same shape as the input grid, but all the values are infinite.
  }
  ◊li{
    Compute the next grid of distances by taking the minimum of the four neighboring cells at each point and capping this value below by the bar height at the same position.
    If some cell misses one of the neighbors, replace the neighbor with zero.
  }
  ◊li{Iterate the previous step until the distance grid converges.}
}

◊p{
  Let us put this in J now.
  We start by constructing the initial matrix of distances.
  We will use the ◊a[#:href "https://code.jsoftware.com/wiki/Vocabulary/dollar"]{◊code{$} (shape of, reshape)} verb for that.
}

◊source-code["j"]{
    NB. We use the inverted cone as our example.
    ] C =.  +/~  (i. _4), (i. 4)
6 5 4 3 3 4 5 6
5 4 3 2 2 3 4 5
4 3 2 1 1 2 3 4
3 2 1 0 0 1 2 3
3 2 1 0 0 1 2 3
4 3 2 1 1 2 3 4
5 4 3 2 2 3 4 5
6 5 4 3 3 4 5 6

    NB. Make an array with the shape of C filled with infinities.
    ($ C) $ _
_ _ _ _ _ _ _ _
_ _ _ _ _ _ _ _
_ _ _ _ _ _ _ _
_ _ _ _ _ _ _ _
_ _ _ _ _ _ _ _
_ _ _ _ _ _ _ _
_ _ _ _ _ _ _ _
_ _ _ _ _ _ _ _
}

◊p{
  That was easy.
  Let us shift the data into all four directions.
  We will need the aptly named ◊a[#:href "https://code.jsoftware.com/wiki/Vocabulary/bardot#dyadicfit"]{◊code{|.!.f} (shift)} verb.
}
◊source-code["j"]{
    D =. ($ C) $ _

    NB. Shift down, fill the space with zeros.

   _1 |.!.0 D
0 0 0 0 0 0 0 0
_ _ _ _ _ _ _ _
_ _ _ _ _ _ _ _
_ _ _ _ _ _ _ _
_ _ _ _ _ _ _ _
_ _ _ _ _ _ _ _
_ _ _ _ _ _ _ _
_ _ _ _ _ _ _ _

    NB. Now shift up.
   1 |.!.0 D
_ _ _ _ _ _ _ _
_ _ _ _ _ _ _ _
_ _ _ _ _ _ _ _
_ _ _ _ _ _ _ _
_ _ _ _ _ _ _ _
_ _ _ _ _ _ _ _
_ _ _ _ _ _ _ _
0 0 0 0 0 0 0 0

    NB. Now left.
   1 |.!.0"1 D
_ _ _ _ _ _ _ 0
_ _ _ _ _ _ _ 0
_ _ _ _ _ _ _ 0
_ _ _ _ _ _ _ 0
_ _ _ _ _ _ _ 0
_ _ _ _ _ _ _ 0
_ _ _ _ _ _ _ 0
_ _ _ _ _ _ _ 0

    NB. Now right.
   _1 |.!.0"1 D
0 _ _ _ _ _ _ _
0 _ _ _ _ _ _ _
0 _ _ _ _ _ _ _
0 _ _ _ _ _ _ _
0 _ _ _ _ _ _ _
0 _ _ _ _ _ _ _
0 _ _ _ _ _ _ _
0 _ _ _ _ _ _ _

    NB. Take the minimum of all four shifts.
    ((_1 & (|.!.0)) <. (1 & (|.!.0)) <. (_1 & (|.!.0)"1) <. (1 & (|.!.0)"1)) D
0 0 0 0 0 0 0 0
0 _ _ _ _ _ _ 0
0 _ _ _ _ _ _ 0
0 _ _ _ _ _ _ 0
0 _ _ _ _ _ _ 0
0 _ _ _ _ _ _ 0
0 _ _ _ _ _ _ 0
0 0 0 0 0 0 0 0
}

◊p{
  We are now ready to define the relaxation function.
}

◊source-code["j"]{
    NB. Take the maximum of the left argument (the original height matrix)
    NB. and minimum of shifted right argument (the distance matrix).
    step =. >. ((_1 & (|.!.0)) <. (1 & (|.!.0)) <. (_1 & (|.!.0)"1) <. (1 & (|.!.0)"1))
}

◊p{
  To apply this function iteratively, we will use the ◊a[#:href "https://code.jsoftware.com/wiki/Vocabulary/hatco"]{◊code{^:} (power of verb)} conjunction (another J word for "verb modifier").
  If we raise a verb to power ◊em{N}, we get a verb that applies the original verb ◊em{N} times in a row.
  If we raise a verb to infinite power ◊a[#:href "https://code.jsoftware.com/wiki/Vocabulary/under"]{◊code{_} (infinity)}, the original verb gets applied until the computation reaches a fixed point.
}

◊source-code["j"]{
    NB. X f^:1 Y   <->   X f Y
    NB. X f^:2 Y   <->   X f (X f Y)
    NB. X f^:3 Y   <->   X f ( X f ( X f Y))

    NB. Step once.
    C step^:1 D
6 5 4 3 3 4 5 6
5 _ _ _ _ _ _ 5
4 _ _ _ _ _ _ 4
3 _ _ _ _ _ _ 3
3 _ _ _ _ _ _ 3
4 _ _ _ _ _ _ 4
5 _ _ _ _ _ _ 5
6 5 4 3 3 4 5 6

    NB. Step twice.
    C step^:2 D
6 5 4 3 3 4 5 6
5 5 4 3 3 4 5 5
4 4 _ _ _ _ 4 4
3 3 _ _ _ _ 3 3
3 3 _ _ _ _ 3 3
4 4 _ _ _ _ 4 4
5 5 4 3 3 4 5 5
6 5 4 3 3 4 5 6

    NB. Apply the step function until convergence.
    C step^:_ D
6 5 4 3 3 4 5 6
5 4 3 3 3 3 4 5
4 3 3 3 3 3 3 4
3 3 3 3 3 3 3 3
3 3 3 3 3 3 3 3
4 3 3 3 3 3 3 4
5 4 3 3 3 3 4 5
6 5 4 3 3 4 5 6

    NB. Package the computation into a function.
    levels =. (>. (_1&(|.!.0) <. 1&(|.!.0) <. _1&(|.!.0)"1 <. 1&(|.!.0)"1)) ^:_ ($&_ @ $)
}

◊p{
  Computing the water volume is easy now: subtract the original height from the water levels and sum up the differences.
}
◊source-code["j"]{
    NB. Water volumes at each position.
    (levels C) - C
0 0 0 0 0 0 0 0
0 0 0 1 1 0 0 0
0 0 1 2 2 1 0 0
0 1 2 3 3 2 1 0
0 1 2 3 3 2 1 0
0 0 1 2 2 1 0 0
0 0 0 1 1 0 0 0
0 0 0 0 0 0 0 0

    NB. Flatten the matrix and sum it up.
    +/, (levels C) - C
40
}
}

◊section{
◊section-title["back-to-2d"]{Looking back at Flatland}

◊p{
  Did we learn anything new about the Flatland after considering three dimensions?
  Yes: for each shortest path algorithm, there is an analogous solution for the two-dimensional case.
}

◊p{
  For example, the analog of the Bellmann-Ford algorithm looks like this:
}
◊ul[#:class "arrows"]{
  ◊li{Start with an array of the same shape as the input filled with infinities.}
  ◊li{
    For each position, compute the minimum of the left and the right neighbors.
    Take the maximum of that value and the height at this position.
  }
  ◊li{Repeat the previous step until convergence.}
}
◊source-code["j"]{
    bf_levels_2d =. (>. (_1&(|.!.0) <. 1&(|.!.0))) ^:_ ($&_ @ $)
    bf_levels_2d H
0 1 1 2 2 2 2 3 2 2 2 1
}
◊p{
  If it was the first solution I heard, I would be quite surprised that it works.
  But once the three-dimensional case paved the way, this solution looks very natural, almost obvious.
}

◊p{
  What would be the analog of the Dijkstra algorithm then?
  Dijkstra gives rise to a very efficient "two-pointer" solution:
}
◊ul[#:class "arrows"]{
  ◊li{Start by placing the left and the right pointers on the boundaries of the input array.}
  ◊li{Keep track of the lowest boundary so far.}
  ◊li{
    Always move the pointer that looks at the lowest height.
    The left pointer moves to the right, the right pointer moves to the left.
  }
  ◊li{If one of the two pointers looks at height ◊em{M} that is greater than the lowest boundary, update the lowest boundary to be ◊em{M}.}
}

◊p{
  That is exactly how a Dijkstra graph search would propagate, always picking the shortest edge to proceed.
  This solution does not map naturally to array languages, so I will write it below in C.
}

◊figure{
 ◊marginnote{The equivalent of the Dijkstra algorithm in the two-dimensional case.}
◊source-code["C"]{
static inline int int_min(int l, int r) { return l < r ? l : r; }

long trapped_water(int H[], int N) {
  if (N == 0) return 0;
  
  long S = 0;
  for (int L = 0, R = N-1, LowBound = int_min(H[L], H[R]); L < R;) {
    int M = int_min(H[L], H[R]);

    if (M < LowBound) S += LowBound - M;
    else LowBound = M;

    if (H[L] < H[R]) L++; else R--;
  }
  return S;
}
}
}
}

◊section{
◊section-title["where-to-go-next"]{Where to go next}
◊p{
  That is all J magic for today!
  If you are confused and intrigued, I can recommend the following resources:
}
◊ul[#:class "arrows"]{
  ◊li{Solve this problem on ◊a[#:href "https://leetcode.com/problems/trapping-rain-water/"]{Leetcode}.}
  ◊li{Watch ◊a[#:href "https://youtu.be/ftcIcn8AmSY"]{Four Solutions to a Trivial Problem}, a talk by Guy Steele where he explores the same problem from different angles.}
  ◊li{Read some ◊a[#:href "https://code.jsoftware.com/wiki/Books"]{Books on J}.}
  ◊li{Listen to the ◊a[#:href "https://arraycast.com/"]{Arraycast podcast}.}
}
}