# Chaining MeTTa Module

This repository contains various experiments on chaining, including
- Backward chaining
- Forward chaining
- Iterative chaining
- Chaining with dependent types
- Chaining with lambda abstraction
- Chaining for modal logic
- Probabilistic backward chaining
- PLN prototype
- PLN based Inference control
- Roman Treutlein's argument set chainer applied on "Light PLN", as a
  git module
- and more

It also contains a MeTTa module of backward and forward chaining
prepared by Hedra Seid Yusuf, though I don't know how well maintained
it is.

## Inference-control benchmark

The reproducible equal-budget comparison of ECAN, the contextual WILLIAM
premise ranker, and their hybrid union is documented in
[`experimental/metamath-aa/pc-xp-union/README.md`](experimental/metamath-aa/pc-xp-union/README.md).
That guide covers installation, pinned dependencies, preflight checks, the
full benchmark command, log analysis, reported results, and limitations.
