locals {
  vpc_cidr      = "10.1.0.0/16"
  azs           = ["ap-northeast-3a", "ap-northeast-3b", "ap-northeast-3c"]
  public_cidrs  = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
  private_cidrs = ["10.1.11.0/24", "10.1.12.0/24", "10.1.13.0/24"]

  common_tags = {
    Project   = "Bunshin"
    ManagedBy = "terraform"
  }
}
