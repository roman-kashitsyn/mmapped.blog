#lang pollen

◊(define-meta title "Book summary: Building a Second Brain")
◊(define-meta keywords "books")
◊(define-meta summary "A summary of the book by Tiago Forte.")
◊(define-meta doc-publish-date "2023-02-25")
◊(define-meta doc-updated-date "2023-02-25")

◊section{
◊section-title["introduction"]{Introduction}
◊p{
  This article summarizes the ◊a[#:href "https://www.buildingasecondbrain.com/"]{Building a Second Brain} book by Tiago Forte.
  The book describes the advantages of ◊a[#:href "https://en.wikipedia.org/wiki/Personal_knowledge_management"]{personal knowledge management} (◊smallcaps{pkm}) systems and offers many tips on using these systems efficiently.
}
}

◊section{
◊section-title["code"]{CODE}
◊p{
Tiago organized the book around the four activities required for maintaining a ◊smallcaps{pkm} system that he describes using the CODE acronym, which stands for ◊quoted{Capture, Organize, Distill, Express.}
Expression is the most crucial part of the process; all other steps exist to facilitate it.
}

◊figure[#:class "grayscale-diagram"]{
  ◊marginnote["mn-code"]{}
  ◊(embed-svg "images/16-code.svg")
}

◊subsection-title["capture"]{Capture}
◊p{
  Capturing is the process of adding new notes to your ◊smallcaps{pkm}.
  Tiago's primary recommendation is not to capture too much:
}
◊ul[#:class "arrows"]{
  ◊li{Think about how you will use the notes before you capture them. We add information to our systems to help us achieve something.}
  ◊li{
    Capture only information that resonates with you, inspires, surprises, and helps your projects and activities.
  }
}
◊p{
  The ◊a[#:href "https://fortelabs.com/blog/12-favorite-problems-how-to-spark-genius-with-the-power-of-open-questions/"]{dozen favorite problems} technique is one way to filter out noise.
  Compile a list of the problems you are most interested in, which are dormant in your mind.
  Every time you read or hear a new result, run it against your problem list.
  If the result seems relevant to one of the problems on your list◊mdash{}capture it.
}

◊subsection-title["organize"]{Organize}
◊p{
  Tiago proposes an outcome-oriented organization system that he abbreviates as ◊a[#:href "https://fortelabs.com/blog/para/"]{◊smallcaps{para}}.
  The crux of the method is classifying your notes into four top-level categories:
}
◊ol-circled{
  ◊li{
    ◊em{Projects} are short-term efforts with a goal and a deadline.
  }
  ◊li{
    ◊em{Areas} are long-term responsibilities that do not have a final goal, but they have a standard you want to meet.
    Finances, travel, health, and family are areas.
  }
  ◊li{
    ◊em{Resources} are topics of interest that might be useful in the future.
    Hobbies (music, calligraphy, etc.) and research subjects (geometry, type systems, cryptography, etc.) are good examples of resources.
  }
  ◊li{
    ◊em{Archives} contain inactive items from other categories.
  }
}
◊p{
  One helpful analogy for the ◊smallcaps{para} system the book mentions is cooking in a kitchen:
}
◊ul[#:class "arrows"]{
  ◊li{Archives are like the freezer. These items wait in cold storage until you need them.}
  ◊li{Resources are like the pantry. These items are available for use in any meal you make but tucked away in the meantime.}
  ◊li{Areas are like the fridge. You want to use these items relatively soon.}
  ◊li{Projects are like the pots cooking on the stove. These are the items on which you are actively working.}
}

◊subsection-title["distill"]{Distill}
◊p{
  One of Tiago's most insightful observations is that we usually find information not when we need it.
  Notes are like messages you send to your impatient and stressed future self.
  It pays off to distill helpful notes to their most essential points to facilitate their future use.
}
◊p{
  One technique that works well is ◊a[#:href "https://fortelabs.com/blog/progressive-summarization-a-practical-technique-for-designing-discoverable-notes/"]{progressive summarization}:
}
◊ul[#:class "arrows"]{
  ◊li{Capture the points that resonated with you in your note as you read the material.}
  ◊li{Use your app's features to highlight the essential passages of the captured note.}
  ◊li{Highlight the keywords within the sentences you highlighted in the previous step (use a different style).}
  ◊li{Write an executive summary at the top of the page in your own words.}
}
◊p{
  Avoid common mistakes people make when applying this technique:
}
◊ul[#:class "arrows"]{
  ◊li{
    Over-highlighting.
    Each summarization layer should include 10◊ndash{}20 percent of the previous material.
  }
  ◊li{
    Highlighting without a purpose.
    Spend time on this activity only when you are trying to create something.
  }
  ◊li{
    Complicating highlighting unnecessarily.
    Do not overthink; rely on your feelings to decide what is essential.
  }
}
◊p{
  It pays off to be lazy.
  Instead of eagerly applying the summarization technique to every note you create, go one step further whenever you access the note.
  This way, you will spend time only on notes that matter and will not lose interest in the technique that requires up-front investment.
}

◊subsection-title["express"]{Express}
◊p{
  Attention is the most precious resource of knowledge workers.
  The purpose of the previous three activities is to help us stay focused when we enter the creative mode.
}
◊p{
  Tiago argues that most projects consist of smaller units or increments that he calls ◊quoted{◊a[#:href "https://fortelabs.com/blog/just-in-time-pm-4-intermediate-packets/"]{intermediate packets}.}
  Use your ◊smallcaps{pkm} to track these knowledge pieces so you can find them quickly when you work on a project where they could be helpful.
  Strive to split your project into chunks and deliver them separately, receiving feedback as soon as possible.
}
◊p{
  According to Tiago, the creative process usually goes through two stages: ◊a[#:href "https://fortelabs.com/blog/divergence-and-convergence-the-two-fundamental-stages-of-the-creative-process/"]{◊em{divergence} and ◊em{convergence}}.
  During the divergence phase, we generate ideas and wander.
  During the convergence stage, we eliminate options and decide what is essential.
  ◊a[#:href "#capture"]{Capture} and ◊a[#:href "#organize"]{Organize} in ◊a[#:href "#code"]{CODE} correspond to the divergence stage; ◊a[#:href "#distill"]{Distill} and ◊a[#:href "#express"]{Express}◊mdash{}to the convergence stage.
}
◊p{
  Tiago also suggests three techniques to boost your creative output:
}
◊ul[#:class "arrows"]{
  ◊li{
    ◊a[#:href "https://fortelabs.com/blog/just-in-time-pm-21-workflow-strategies/"]{◊em{Archipelago of ideas}}: start creative work not from a blank slate but from an outline filled with notes and quotes.
    This way, you separate the activity of choosing ideas (divergence) from the act of arranging them (convergence).
    These activities benefit from different states of mind.
  }
  ◊li{
    ◊a[#:href "https://medium.com/@mstine/day-6-how-you-can-use-hemingways-bridge-to-ship-today-s-momentum-to-tomorrow-a1af14e300ef"]{◊em{Hemingway bridge}}: stop working when you have clear next steps.
    This technique will make picking up the project the next day easier.
    If you are putting a project on hold, write a note with the path forward and the context that will help you resurrect the project.
  }
  ◊li{
    ◊em{Dial down the scope}: reduce the project size to fit into the deadline instead of moving the deadline.
    Cut unfinished ideas and use them for future projects.
    Ship something small and concrete.
  }
}
}

◊section{
◊section-title["habits"]{PKM habits}
◊p{
  Tiago compares maintaining your ◊smallcaps{pkm} to ◊a[#:href "https://en.wikipedia.org/wiki/Mise_en_place"]{mise en place}, a set of habits that cooks use to keep their workplace clean and organized.
  He mentions a few helpful routines for managing a second brain:
}
◊ul[#:class "arrows"]{
  ◊li{
    Create checklists for starting and finishing a project.
    Use them to ensure that you handle projects consistently.
  }
  ◊li{
    Review your life ◊a[#:href "https://fortelabs.com/blog/the-weekly-review-is-an-operating-system/"]{weekly}, ◊a[#:href "https://fortelabs.com/blog/the-monthly-review-is-a-systems-check/"]{monthly}, and ◊a[#:href "https://fortelabs.com/blog/the-annual-review-is-a-rearchitecture/"]{annually}.
    Search for recurring themes and check whether you want to change something.
  }
  ◊li{
     Notice small opportunities to improve your notes and make them more discoverable.
  }
}
}
◊section{
◊section-title["resources"]{Resources}
◊ul[#:class "arrows"]{
  ◊li{
    Popular notetaking apps and plugins: ◊a[#:href "https://evernote.com/"]{Evernote}, ◊a[#:href "https://obsidian.md/"]{Obsidian}, ◊a[#:href "https://logseq.com/"]{Logseq}, ◊a[#:href "https://roamresearch.com/"]{Roam Research}, ◊code-ref["https://www.orgroam.com/"]{org-roam}.
  }
  ◊li{
    ◊a[#:href "https://www.buildingasecondbrain.com/resources"]{How to Choose Your Notetaking App}.
  }
}
}