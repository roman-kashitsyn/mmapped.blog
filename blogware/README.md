# Blogware

This package contains a simplistic compiler from a tiny subset of LaTeX to HTML.
It's not a general-purpose tool and supports only features I care about.

## The syntax

### Commands

Commands have the following general shape:

```
\commandname[options]{arg1}{arg2}{...}
```

Where `options` are a comma-separated list of symbols, and `body` is an arbitrary mix of text, commands, environments, etc.
The options list is optional, and the number of arguments depends on the command.

Examples:

```tex
\pi                   % a nullary command with no options
\b{bold text}         % a command with one argument
\section{label}{Name} % a command with two required arguments
```

### Environments

Environments have the following general shape:

```
\begin{envname}[options]{args}
\end{envname}
```

The contents of the arguments depends on the environment.

Examples:

```tex
% Start a diagram
\begin{figure}[grayscale]
  \caption{Description of the diagram}
  \includegraphics{images/diagram.svg}
\end{figure}
```

### Sections and subsections

Unlike in LaTeX, sections are not numbered.
They also have an extra required argument: the section label name.

```tex
\section{sec-label}{Section name}
\subsection{subsec-label}{Subsection name}
```

### Comments
