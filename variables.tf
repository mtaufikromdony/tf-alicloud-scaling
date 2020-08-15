  variable "region" {
    description = "Alibaba Cloud region"
    type        = string
  }

  variable "zone" {
  type        = string
  description = "Alibaba Cloud availability zone"
  }

  variable "instance_type" {
    description = "Alibaba ECS Instance type."
    type        = string
  }

  variable "type" {
  type        = string
  description = "type of security group"
  }