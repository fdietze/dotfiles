---
description: Read this whenever working with projects of any kind. creating projects, working on projects, managing projects, ...
---

# Managing Projects

- All my projects are in ~/projects
- every project is a separate directory: ~/projects/<my-project>
- to the user: This file MUST only be modified by hand. yes, I'm prompting you.

# Creating new Project
- Ask the user clarifying questions about the scope and main architectural decisions of the project. Wait for the user's response.
- before creating any files or executing any commands, write down a plan (consult the planning agent) of what needs to be done and in which order it should be done. wait for the confirmation of the user.
- to create a new project we need a name first, which becomes the folder name. check if a project with that name already exists and abort if there is one. If everything is green, create the directory ~/projects/<my-project>. You must never create a project in the home directory directly.
- If I don't provide a name, you present 3 names to me as a multiple-choice question. it must be funny names based on what you learned about the new project so far and the names of the rest of the projects.
- enter that new directory
- `git init`
- echo "use flake" > `.envrc`
- minimal flake.nix that satisfies the user request
- when using nixpkgs, use nixpkgs-unstable
- stage flake.nix, so nix can work with it
- direnv allow
- Create a very simple but informative Readme.
- Add an AGENTS.md that 
- Add an AGENTS.md must include
    - a precise description of the whole setup and architecture main data flow
    - interfaces of this software to the outside world. UI? Open ports? CLI?
    - it must include that the setup in AGENTS.md and the README.md MUST always be kept up to date.
- use a justfile for the clean set of commands covering the setup (often pointing to nix commands) (install just in the nix flake development shell)

## Development
- Provide a straightforward and simple development environment with file watching and hot reloading
- use direnv with nix flakes
- nix commands to build the necessary artifacts
- If multiple processes are required, use a modern process manager

## Verification
- if there is a standard way for code verification appropriate for the used technologies, use them.
- all pure functions and algorithms must be covered with unit tests. from trivial cases over simple examples to difficult edge cases. Keep the number small but not too small.
- When everything is green, run the development setup

## Nix and reproducibility
- Nix is the source of truth for tooling, build logic, and deployment artifacts.
- The deployed runtime should come from Nix, not from an unpinned external base image.
- If reproducibility matters, generating a Dockerfile is not enough; the runtime itself must also come from Nix.
- Prefer one clear path from local development to production over multiple partially overlapping workflows.
- Pin all version of all tools.
- If there is a modern de-facto standard for tools from the nix community on how to do <x>, use it.
- If the technologie's dependencies can be managed so that builds can be cached with nix and there are well-established tools for that, use them.
- use nix for wiring and plumbing of settings and be the source of truth for all configuration

# Tools
- If available, use well-established faster native versions of traditional tools. For example tsgo, swc, etc.

# Technologies and Dependency setup
- If no technology has been specified, prefer the modern and well-established de-facto standard stack, but on the smart side
- If realistic, prefer native languages with strong static analysis and verification capabilities and mature ecosystems like Rust.
- Use idiomatic project setup where compatible with nix

# Specific Technologies
- for python use uv
- for npm dependencies use pnpm
- for machine learning use pytorch or rust/burn
- for rust, use a modern flake based system to set up rust and pin the rust version and build targets. Use latest stable rust, or even nightly if appropriate.
- for websites if using CDN dependencies, always use security hashes, but in general prefer managed dependencies and a bundler over CDN


# Architecture Principles to follow
- Keep It Simple, Stupid (KISS): Avoid unnecessary complexity in design and
  implementation.
- You Ain’t Gonna Need It (YAGNI): Do not add functionality until it is
  demonstrably necessary.
- Don’t Repeat Yourself (DRY): Every piece of knowledge must have a single,
  unambiguous representation.
- Separation of Concerns (SoC): Divide the system into distinct sections with
  minimal overlap in functionality.
- Minimize Cognitive Load: Design systems that are as easy as possible to
  understand and reason about.
- High Cohesion, Low Coupling: Keep related code together and reduce
  dependencies between modules.
- Functional Core, Imperative Shell: Isolate side-effects to the outermost
  layers of the application.
- Vertical Slice Architecture: Structure code around business capabilities or
  features, not technical layers.
- SOLID Principles: A set of five fundamental principles for object-oriented
  design.
- Single Responsibility Principle (SRP): A class or module should have one, and
  only one, reason to change.
- Law of Demeter (Principle of Least Knowledge): A module should not know about
  the internal details of the objects it manipulates.
- Tell, Don’t Ask: An object should command another object to perform an action,
  rather than asking for its state.
- Make Illegal States Irrepresentable: Use the type system to ensure that
  invalid data cannot exist.
- Parse, Don’t Validate: Transform un-trusted input into a validated domain
  model at the system boundary.
- Correctness by Construction: Design components so they can only be created in
  a valid state.
- Prefer Compile-Time Errors over Runtime Errors: Maximize the number of errors
  that can be caught by the compiler.
- Favor Immutability: Prefer data structures that cannot be modified after they
  are created.
- Design by Contract: Be explicit about the preconditions, postconditions, and
  invariants of components.
- Design for Testability: Structure the system to allow for easy and effective
  unit and integration testing.
