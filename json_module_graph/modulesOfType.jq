include "library";

def modulesOfType($arg):
  [.[] | select(.Type == $arg) | .Name] | unique
;

modulesOfType($arg)