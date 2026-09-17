variable "project_name" {
  description = "Project identifier used in resource names."
  type        = string
}

variable "environment" {
  description = "Environment identifier used in resource names."
  type        = string
}

variable "certificate_file" {
  description = "Local path to the PEM-encoded certificate body."
  type        = string
}

variable "private_key_file" {
  description = "Local path to the unencrypted PEM private key. The value is passed through the write-only ACM argument."
  type        = string
}

variable "certificate_version" {
  description = "Monotonic version used to trigger re-import after rotating the local certificate."
  type        = number
  default     = 1
  nullable    = false
}
