// Your Chrome profiles, in the order the picker shows them.
//
// Copy this file to Profiles.swift, edit the list, then run ./build.sh.
// Profiles.swift is ignored by git, so your own list stays on your machine.
//
// `dir` is the profile's folder name. To find it, open chrome://profile-internals in
// Chrome, click a profile to expand it, and take the last part of its "Profile Path"
// (for example "Default" or "Profile 1"). `name` is whatever you want the picker to show.
//
// Only list folders that exist: Chrome creates a new, empty profile when it is given a
// folder name it doesn't know.
let profiles: [Profile] = [
    Profile(dir: "Default", name: "Personal"),
    Profile(dir: "Profile 1", name: "Work"),
]
