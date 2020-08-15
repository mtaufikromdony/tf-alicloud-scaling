terraform { # Terraform related configs
  backend "local" { # We use local backend to keep it simple
    path = "terraform.tfstate" # The file where the Terraform states stores in
  }
}