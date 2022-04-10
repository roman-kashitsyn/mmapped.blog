#lang pollen

◊(define-meta title "Debug like Feynman, test like Faraday")
◊(define-meta keywords "programming,glasperlenspiel")
◊(define-meta summary "Apply scientific method in everyday software engineering.")
◊(define-meta doc-publish-date "2022-04-01")
◊(define-meta doc-updated-date "2022-04-01")

◊p{
  Complex systems are all around us.
}

◊p{
  The biggest mystery of all is the laws governing our universe.
  It is remarkable that physicists figured out good approximations of these laws and can now predict a wide range of natural phenomena, from the movement of planets to the behavior of subatomic particles.
  They did not even get the source code (that is why it took somewhat long).
}
◊p{
  Our bodies are marvelously complex.
  The source code for making them is public, but the execution semantics is beyond our comprehension.
  Yet physicians can eradicate smallpox, replace hearts, and even help with your migraine.
}
◊p{
  One of the main tools that helped humans achieve such stellar results is the ◊a[#:href "https://en.wikipedia.org/wiki/Scientific_method"]{scientific method}, a collection of principles scientists use to acquire knowledge.
  The process is quite simple:
}
◊ol-circled{
  ◊li{Start with an idea you want to check.}
  ◊li{Use logic to deduce a testable prediction from that idea.}
  ◊li{Conduct an experiment.}
  ◊li{Analyze the results.}
}
◊p{
  One non-obvious detail of the scientific method hides in the second step.
  The goal of the experiment is to ◊em{disprove} the prediction.
  The default assumption is that there is no Higgs boson and that the new medication under test does not have any effect.
  There are infinitely many ideas, most of them have nothing to do with reality.
  If you look hard enough, you can find arguments for those ideas.
  The goal of the scientific method is to throw away bad ideas as efficiently as possible.
}
◊p{
  Before we had the scientific method, we understood the world around us through the lens of arbitrary apriori beliefs,
  such as that ◊a[#:href "https://en.wikipedia.org/wiki/Geocentric_model"]{the Earth is the center of the universe},
  that ◊a[#:href "https://en.wikipedia.org/wiki/Humorism"]{all illnesses come from the disbalance of bodily fluids},
  or that ◊a[#:href "https://en.wikipedia.org/wiki/Smalltalk"]{everything should be an object}.
}
◊p{
  A few years ago, it dawned on me that debugging a program is similar to conducting scientific experiments.
  Of course, I was not the first one who had this bright idea.
  Andreas Zeller, the author of ◊a[#:href "https://www.gnu.org/software/ddd/ddd.html"]{GNU Data Display Debugger}, wrote a ◊a[#:href "https://www.whyprogramsfail.com/"]{book} on systematic debugging.
}

◊p{
  However, scientific analogies go far beyond debugging.
  Science is about understanding and describing complex systems, which is a large part of what programmers do (the other part being constructing overly complex systems that others have to understand and describe).
  In this article, we shall look at the similarities between tinkering with software and scientific endeavors and learn a thing or two from the giants on whose shoulders we stand.
}

◊section["record-your-observations"]{Record your observations}
◊blockquote{
  First we have an observation, then we have numbers that we measure, then we have a law which summarizes all the numbers.
  But the real glory of science is that we can find a way of thinking such that the law is evident.
  ◊br{}
  [Richard Feynman, The Feynman Lectures on Physics, Volume I, Mainly Mechanics, Radiation, and Heat]
}

◊p{
  It is only a few weeks before the next major release, and you have just encountered a critical bug.
  You open the bug tracker and search for the error message.
  Great, there is an issue with a promising title!
  Your former teammate closed it a year ago.
  Full of hope, you open the issue.
  All you see is ◊em{status: done, resolution: fixed}.
  It seems that you are going to have a long day.
}

◊p{
  Does this story sound familiar?
  Few things are more disappointing than opening a fixed bug report and learning absolutely nothing from that report.
}

◊p{
  The first activities that make you a scientist are observation and recording.
  Tried something that did not work?
  Record this in the ticket.
  Avoid ◊a[#:href "https://en.wikipedia.org/wiki/Publication_bias"]{publication bias}.
  Negative results are significant, too.
  Found the culprit?
  Document the details of the problem and the solution for posterity.
}

◊p{
  It might sound like a waste of time, but it is not.
}
◊ul[#:class "arrows"]{
  ◊li{
    The best way to understand anything is to write it down.
    You might find flaws in your analysis once you put it in words.
  }
  ◊li{You create evidence that you are a professional.}
  ◊li{You transfer your knowledge and enable others to follow your steps and to learn from your experience.}
}

◊p{
  Many important discoveries would be impossible without detailed, carefully recorded measurements.
  Without a lifetime of Tycho Brahe's astronomical observations, Johannes Kepler would not have discovered his ◊a[#:href "https://en.wikipedia.org/wiki/Kepler%27s_laws_of_planetary_motion"]{laws of planetary motion}.
  You should now record your observations about that bug you are working on.
  Maybe your data will help someone get a Turing Award one day?
}

◊section["test-causality"]{Test causality}
◊blockquote{
  In the strict formulation of the law of causality—if we know the present, we can calculate the future—it is not the conclusion that is wrong but the premise.
  ◊br{}
  [Werner Heisenberg]
}
◊p{
  Phew, hunting down that bug took you a while.
  You apply a patch, add a unit test demonstrating the problem, see the test passing, and land the change on the main branch.
  The next day, you learn that the bug is still reproducible.
  How could that happen?
}

◊p{
  Many programmers write tests ◊em{after} the code is complete.
  I am sure you did this.
  I certainly did—many times.
}

◊p{
  Sadly, if we apply basic logic, this approach makes no sense.
  How can you be sure that it is your implementation ◊em{causing} the tests to pass?
  The implication ◊em{implementation ⇒ test pass} proves merely a ◊a[#:href "https://en.wikipedia.org/wiki/Correlation"]{correlation}.
  We also need to show ◊em{not(implementation) ⇒ not(test pass)} to prove ◊a[#:href "https://en.wikipedia.org/wiki/Causality"]{causation}.
}
◊p{
  "What else could be causing tests to pass?" you might say.
  I do not know, neither do you.
  Maybe your test code has a bug, or does not trigger the relevant code path.
  You do not know until you try.
}
◊p{
  Remember the scientific method?
  The experiment should try to disprove your belief.
  Running tests after the implementation is complete is like testing a new drug without having a control group.
}
◊p{
  If you are fixing a bug, the logical approach is the following:
}
◊ol-circled{
  ◊li{Write a test reproducing the bug. Ensure that the test fails with the expected error.}
  ◊li{Apply the change that addresses the bug.}
  ◊li{Check if the test passes.}
}
◊p{
  Congratulations, you demonstrated that your fix makes the problem disappear (assuming the test is deterministic, and your fix was the only difference between test runs).
  If you cannot force yourself to write the test first, check that breaking the code again makes the test fail.
}
◊p{
  It seems that apologists of ◊a[#:href "https://en.wikipedia.org/wiki/Test-driven_development"]{test-driven development} are onto something, though I have never heard the causality argument from them.
  Unfortunately, there is no tooling checking that each test you write used to fail before it became green.
}

◊section["know-your-data"]{Know your data}
◊blockquote[#:cite "https://www.atomicarchive.com/resources/documents/trinity/fermi.html"]{
  About 40 seconds after the explosion the air blast reached me.
  I tried to estimate its strength by dropping from about six feet small pieces of paper before, during and after the passage of the blast wave.
  Since at the time, there was no wind I could observe very distinctly and actually measure the displacement of the pieces of paper that were in the process of falling while the blast was passing.
  The shift was about 2 ◊string->symbol{frac12} meters, which, at the time, I estimated to correspond to the blast that would be produced by ten thousand tons of T.N.T.
  ◊br{}
  [Enrico Fermi, My Observations During the Explosion at Trinity on July 16, 1945]
}
◊p{
  A guy from the OPS team stops by your desk.
  You feel uncomfortable because you forgot his name again.
}
◊p{
  ◊string->symbol{mdash} Hi! I need to buy machines for that new project you are working on.
  How many servers do we need?
  Where do we need to place them? 
  How much disk and RAM should they have?
}
◊p{
  Your ears become red.
}
◊p{
  ◊string->symbol{mdash} Ahm, how could I know? I'm a software guy!
}

◊p{
  Software engineers are obsessed with code.
  We stare at it for hours every day.
  We fight about the way to place braces and the perfect number of spaces to use for indentation.
  We can argue with a religious zeal about the name of a function or a variable.
}
◊p{
  Yet the most precious substance, the DATA flowing through our code, often gets little attention.
  It hides from us behind variables with descriptive names.
}
◊p{
  Why is data important anyway?
  The code works for arbitrary inputs, right?
}
◊p{
  Imagine that you need to sort a large pile of cards with numbers typed on them.
  What algorithm would you use?
  Would you use the same algorithm if there were a billion of these cards?
  Would you use the same algorithm if all the numbers were zero or one?
}

◊p{
  Knowing the shape and distribution of the inputs and outputs of your program helps you find simple and efficient designs, come up with optimizations, and spot anomalies during debugging sessions.
  But there is another source of data: the program itself.
  What is the median time that your system needs to process a single request?
  What database queries take the longest time on average?
}

◊p{
  Yet another valuable source of data is the environment in which your programs execute.
  How long does it take to write a block to disk?
  How long does it take to spawn a thread?
  What are the latency and the throughput of the network connection between the data centers hosting your program?
}

◊p{
  There are plenty of tools helping you record, collect, and display the data, from ◊a[#:href "https://rdtools.readthedocs.io/en/stable/"]{RdTools} to ◊a[#:href "https://prometheus.io/"]{Prometheus} and ◊a[#:href "https://grafana.com/"]{Grafana}.
  But you do not have to use any of them to start paying attention to your data.
  Recording events and stats into a file might be good enough for you.
  The ◊a[#:href "https://carlos.bueno.org/optimization/"]{Mature Optimization Handbook} will help you to get started.
}

◊p{
  Having all these data at your disposal will enable you to perform ◊a[#:href "https://en.wikipedia.org/wiki/Back-of-the-envelope_calculation"]{back-of-envelope calculations}, of which Enrico Fermi was an absolute master.
  Next time that OPS guy comes to your desk, you will have an answer for him.
}

◊section["debug-mental-models"]{Debug mental models}

◊blockquote{
  So the guy says, "What are you doing? You come to fix the radio, but you're only walking back and forth!"
  I say, "I'm thinking!" 
  ◊br{}
  [Richard Feynman, "Surely You're Joking, Mr. Feynman!", "He Fixes Radios by Thinking!"]
}

◊p{
  Your team lead rushes into your cubicle and tells you that the production system is barely working.
  You look at the symptoms and have no clue where to start.
  You launch the debugger and step through the code.
  Two hours later, you still have no clue.
}

◊p{
  Debuggers are immensely useful.
  Launching a debugger should be your first reaction if your application crashes with a core dump or hangs forever.
  In some areas of computing, however, using a debugger is hard or impossible.
  One example is distributed computing:
}

◊ul[#:class "arrows"]{
  ◊li{
    The software runs on servers you might not have direct access to.
  }
  ◊li{
    The software needs to reply to heartbeats.
    Attaching a debugger would stop the process, and in a few seconds, the network would assume that the node you debug is dead, making further debugging impossible.
    That is an excellent example of the ◊a[#:href "https://en.wikipedia.org/wiki/Observer_effect_(physics)"]{observer effect}.
  }
  ◊li{
    The bug reveals itself only under a heavy load.
  }
  ◊li{
    The bug results from a complex interaction of multiple processes distributed across the network.
    Try stepping through that.
  }
}

◊p{
  There is a skill that makes a debugger unnecessary most of the time: creating good mental models.
  As ◊a[#:href "https://en.wikipedia.org/wiki/Linus_Torvalds"]{Linus Torvalds} put it in ◊a[#:href "https://lkml.org/lkml/2000/9/6/65"]{one of his famous emails about debuggers},
}

◊blockquote[#:cite "https://lkml.org/lkml/2000/9/6/65"]{
  It's that you have to look at the level ◊em{above} sources.
  At the meaning of things.
  Without a debugger, you basically have to go the next step: understand what the program does.
  Not just that particular line.
}

◊p{
  Or as ◊a[#:href "https://en.wikipedia.org/wiki/Rob_Pike"]{Rob Pike} wrote about ◊a[#:href "https://en.wikipedia.org/wiki/Ken_Thompson"]{Ken Thompson} in ◊a[#:href "https://www.informit.com/articles/article.aspx?p=1941206"]{The Best Programming Advice I Ever Got}:
}

◊blockquote[#:cite "https://www.informit.com/articles/article.aspx?p=1941206"]{
  When something went wrong, I'd reflexively start to dig in to the problem, examining stack traces, sticking in print statements, invoking a debugger, and so on.
  But Ken would just stand and think, ignoring me and the code we'd just written.
  After a while I noticed a pattern: Ken would often understand the problem before I would, and would suddenly announce, "I know what's wrong."
  He was usually correct.
  I realized that Ken was building a mental model of the code and when something broke it was an error in the model.
  ◊br{}
  [Rob Pike, "The Best Programming Advice I Ever Got"]
}

◊p{
  You are probably skeptical at this point (you should be).
  I talked about the scientific method, logic, and experiments, and most of this section is a plain argument from authority.
  However, mental models nicely fit into the scientific method: you need models to interpret observations.
  Each bug report is an unexpected result of an experiment; a good model will help you backtrack from the outcome to a potential cause and develop a new hypothesis to test.
}

◊p{
  How do you build a good mental model?
  I do not think there is a universal answer.
  Different people will prefer to use various analogies depending on their background and the system.
  My default tactic is to concentrate on the inputs and outputs first, depicting the system as a large box with data pipes going in and out (I use steel pipes for data in my head, you might prefer plastic).
  I then think of the system's essential components and their data-pipe wiring.
  I recursively apply the same process to each component.
  As you can see, the resulting picture forms a fractal.
  I can mentally zoom in and out to concentrate on the part relevant to the current task.
}

◊blockquote{
  I had a scheme, which I still use today when somebody is explaining something that I'm trying to understand: I keep making up examples.
  For instance, the mathematicians would come in with a terrific theorem, and they're all excited.
  As they're telling me the conditions of the theorem, I construct something which fits all the conditions.
  You know, you have a set (one ball) — disjoint (two balls).
  Then the balls turn colors, grow hairs, or whatever, in my head as they put more conditions on.
  Finally they state the theorem, which is some dumb thing about the ball which isn't true for my hairy green ball thing, so I say, "False!"
  ◊br{}
  [Richard Feynman, "Surely You're Joking, Mr. Feynman!", "A Different Box of Tools"]
}

◊p{
  You might prefer encoding your models as actors, state machines, or balls.
  Pick whatever clicks with your brain.
}

◊section["formalize-your-models"]{Formalize your models}

◊blockquote{
  In every department of physical science there is only so much science, properly so-called, as there is mathematics.
  ◊br{}
  [Immanuel Kant]
}

◊p{
  You are proud of your multi-threaded lock-free queue implementation.
  Your colleagues reviewed it thoroughly and agreed that it is correct.
  Hours of testing did not reveal any issues.
  After two weeks in production, servers start to hang.
}

◊p{
  Physics requires knowledge and an intuitive understanding of a lot of hairy math.
  Physicists use all sorts of analogies and intuition in their work, but equations and experiments are what matters in the end.
  You leave your mark in theoretical physics by deriving an equation that gets named after you.
}

◊p{
  Most programmers will tell you that you do not need to know math to be good at programming.
  There is some truth to this statement: you can make a lot of money in the industry even if you have never attended abstract algebra classes.
  But as you grow as a professional, you will eventually hit the ceiling.
  Math is what elevates you to the next level.
}

◊p{
  Math is also one of the few universal languages that we have.
  Luckily, most of the systems we build need only basic math: set theory, first-order logic, and discrete math.
  One way to use math for your benefit is to turn your vague mental model of the system into a precise formal specification, enabling other people to understand the model.
  Even if the spec will be so simple it borders on the trivial (most good specs are), this exercise will give you a crystal-clear understanding of what your system should do.
}
◊p{
  But it gets better.
  Once you have a formal specification, you can feed it to a computer and start asking interesting questions.
  ◊a[#:href "https://lamport.azurewebsites.net/video/videos.html"]{TLA+} is a powerful and accessible toolbox that can help you write and check formal specifications.
  This is the system that the Amazon Web Services team used to build their critical systems (see ◊a[#:href "https://lamport.azurewebsites.net/tla/formal-methods-amazon.pdf"]{How Amazon Web Services Uses Formal Methods}, Communications of the ACM, Vol. 58 No. 4, Pages 66-73).
}
◊p{
  ◊a[#:href "https://www.linkedin.com/in/chenghuang/"]{Cheng Huang}, a principle engineering manager at Microsoft, ◊a[#:href "https://lamport.azurewebsites.net/tla/industrial-use.html"]{wrote}:
}
◊blockquote[#:cite "https://lamport.azurewebsites.net/tla/industrial-use.html"]{
  TLA+ uncovered a safety violation even in our most confident implementation.
  We had a lock-free data structure implementation which was carefully design & implemented, went through thorough code review, and was tested under stress for many days.
  As a result, we had high confidence about the implementation.
  We eventually decided to write a TLA+ spec, not to verify correctness, but to allow team members to learn and practice PlusCal.
  So, when the model checker reported a safety violation, it really caught us by surprise.
  This experience has become the aha moment for many team members and their de facto testimonial about TLA+.
  ◊br{}
  [Leslie Lamport, Industrial Use of TLA+]
}
◊p{
  I wish I have learned about TLA+ much earlier in my career.
  Unlike other formal methods I tried, this tool is easy to pick up.
}

◊section["question-method"]{Question your method}
◊blockquote{
  There’s nothing quite as frightening as someone who knows they are right.
  ◊br{}
  [Michael Faraday]
}

◊p{
  A new manager joined your team two months ago.
  Since then, you started practicing ◊a[#:href "https://www.scrum.org/"]{Scrum}: you work in ◊a[#:href "https://www.scrum.org/resources/what-is-a-sprint-in-scrum"]{sprints} on ◊a[#:href "https://www.atlassian.com/agile/project-management/user-stories"]{user stories}, play ◊a[#:href "https://en.wikipedia.org/wiki/Planning_poker"]{planning poker}, groom your ◊a[#:href "https://www.atlassian.com/software/jira"]{Jira} tickets, and hold ◊a[#:href "https://www.scrum.org/resources/what-is-a-sprint-retrospective"]{retrospective} and ◊a[#:href "https://www.agile-academy.com/en/scrum-master/daily-standup/"]{daily standup} meetings.
  Your users are just as unhappy and frustrated as they were two months ago.
}
◊p{
  We are living in the best of times.
  The ideas of rapid iteration, ◊a[#:href "https://agilemanifesto.org/"]{agile development}, and ◊a[#:href "https://continuousdelivery.com/"]{continuous delivery} are taking over the world.
  Software shops are churning features at a stunning rate.
}
◊p{
  We are living in the worst of times.
  Our software is bloated, slow, and buggy.
  Our interfaces are overly complicated, often on the border of being enraging.
  Our users are frustrated and depressed.
  Try ◊a[#:href "https://images.google.com/?q=frustration"]{searching Google images for "frustration."}
  How many pictures have computers on them?
}
◊p{
  The amount of material on software development methodology is overwhelming.
  ◊a[#:href "https://agilemanifesto.org/"]{Agile}, ◊a[#:href "https://en.wikipedia.org/wiki/Extreme_programming"]{XP}, ◊a[#:href "https://scrum.org"]{Scrum}, ◊a[#:href "https://en.wikipedia.org/wiki/Kanban_(development)"]{Kanban}, ◊a[#:href "https://www.lean.org/"]{Lean}, ◊a[#:href "https://en.wikipedia.org/wiki/Test-driven_development"]{TDD}, ◊a[#:href "https://en.wikipedia.org/wiki/Behavior-driven_development"]{BDD}, and the list goes on.
  It is easy to get the impression that everyone knows the best way to develop software but you.
  This impression is false.
  No one has a clue.
}
◊p{
  Many project management techniques focus on being ◊em{efficient} and producing more features in less time.
  This goal is fundamentally flawed.
  We should not be after efficiency.
  In my experience, the main problem with software is that people waste time on non-essential work.
}
◊p{
  Note that the same rule applies to personal productivity.
  You become productive not by packing your day with tasks but by clearing up room for things that matter.
  If you have not read ◊a[#:href "https://www.amazon.com/-/en/dp/1455586692"]{Deep Work} yet, do it.
  This book will change your life.
}
◊p{
  So we want to throw out insignificant ideas and focus on the relevant ones.
  Does it sound familiar?
  The scientific method can also help us with the creative side of software engineering.
}
◊p{
  Assume Ben thinks that implementing feature X is essential.
  We enter the first step of the scientific method.
  How can we prove Ben wrong?
}
◊ul[#:class "arrows"]{
  ◊li{
    Think of the most straightforward experiment that can reject Ben's belief.
    Looking at the contents of your database or implementing a prototype and gathering usage statistics, for example.
  }
  ◊li{
    Conduct the "experiment": go look at the data, implement the most straightforward solution, or gather user feedback.
    Your solution does not have to be perfect right away.
    Remember, we do not want to waste our life polishing features that make no difference.
  }
  ◊li{
    Analyze the outcome.
    Users do not care?
    Remove the feature.
    Users love the feature and want it to be polished?
    Congratulate Ben and go back to step one.
  }
}
◊p{
  This approach is similar to the iterative development promoted by agile methodologies and extreme programming.
  Note how we came to this idea naturally by applying our analogy.
  In this light, the ◊a[#:href "https://en.wikipedia.org/wiki/Waterfall_model"]{waterfall model} is similar to postulating a theory from apriori principles: an approach doomed to fail.
  Does this mean that you need a scrum master to be productive?
  It seems unlikely to me, but I am sure you know how to check ideas at this point.
}
◊p{
  Be critical of your method.
  Blindly following the procedures should not feel right to you.
  Challenge the status quo, stop, and think.
  ◊em{Why am I doing this?} ◊em{Is it worth my time?}
}

◊section["conclusion"]{Conclusion}
◊p{
  Software engineering is applied science, even though it does not always feel like it.
  We are lucky because our experiments are cheap and easy to replicate.
  We can iterate and learn from our mistakes much quicker than researchers in more traditional fields.
  On the other hand, we tend to ignore centuries of experience accumulated by mainstream science.
  Being aware of the scientific methodology and insights will help you build better systems faster and have more fun.
}
◊p{
  The next time you debug that legacy system, be proud of who you are: a scientist a few steps away from discovery.
}

◊p{
  ◊a[#:href "https://www.reddit.com/r/programming/comments/ttld4n/1st_april_blog_post_debug_like_feynman_test_like/"]{Discuss this article on Reddit.}
}

◊section["acknowledgements"]{Acknowledgements}
◊p{
  Thanks to Nikolay Komarevskiy for his suggestions for the original version of this article.
}