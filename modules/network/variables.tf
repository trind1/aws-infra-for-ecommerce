variable "project_name" {
  description = "Project identifier used in resource names."
  type        = string
}

variable "environment" {
  description = "Environment identifier used in resource names and tags."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid CIDR block."
  }
}

variable "availability_zones" {
  description = "Exactly two Availability Zones, one for each subnet pair."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) == 2 && length(distinct(var.availability_zones)) == 2
    error_message = "availability_zones must contain exactly two distinct Availability Zones."
  }
}

variable "public_subnet_cidrs" {
  description = "Exactly two public subnet CIDRs ordered like availability_zones."
  type        = list(string)

  validation {
    condition = length(var.public_subnet_cidrs) == 2 && alltrue([
      for cidr in var.public_subnet_cidrs : can(cidrnetmask(cidr))
    ])
    error_message = "public_subnet_cidrs must contain exactly two valid CIDR blocks."
  }
}

variable "database_subnet_cidrs" {
  description = "Exactly two private database subnet CIDRs ordered like availability_zones."
  type        = list(string)

  validation {
    condition = length(var.database_subnet_cidrs) == 2 && alltrue([
      for cidr in var.database_subnet_cidrs : can(cidrnetmask(cidr))
    ])
    error_message = "database_subnet_cidrs must contain exactly two valid CIDR blocks."
  }
}
