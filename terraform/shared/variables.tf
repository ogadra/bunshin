variable "aws_profile" {
  description = "AWS CLI profile for the aws provider so apply targets the intended account"
  type        = string

  validation {
    condition     = length(var.aws_profile) > 0
    error_message = "aws_profile must not be empty."
  }
}
