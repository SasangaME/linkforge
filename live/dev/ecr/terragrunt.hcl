include "root" {
  path = find_in_parent_folders("root.hcl")
}

inputs = {
  force_delete = true
}
