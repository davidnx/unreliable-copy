# Unreliable-Copy: fast resume wrapper over robocopy

Copies files recursively and efficiently from a source location to a destination location
with fast resume after failures at file boundaries (i.e. individual file copies are never retried).

Designed to deal with `source` filesystem unreliability (i.e. `source` could e.g. disappear halfway through a copy)
as well as compute unreliablity (i.e. the script may be ungracefully terminated at any point)
by keeping track of progress using the destination only.

* Example use case: backing up files from an unreliable machine that constantly reboots ungracefully.
This script provides significantly faster resume than something like `robocopy $src $dest /MIR`
because it does not need to touch files that were copied previously.

Time complexity of resuming a copy with this script is `O(depth)` (depth of the folder structure where the last failure happened),
whereas robocopy is `O(N)` (number of files already copied). In practice, `O(depth)` is commonly `O(1)`.

# Disclaimer

Use at your own risk. This script has NOT been carefully tested, and was written as a quick exercise to solve a practical problem.
