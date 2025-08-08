variable "region" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "us-east-1"
}

variable "glue_database_name" {
  description = "The name of the Glue database"
  type        = string
  default     = "fifa"
}

variable "glue_table_name" {
  description = "The name of the Glue table"
  type        = string
  default     = "players"
}

variable "glue_crawler_name" {
  description = "The name of the Glue crawler"
  type        = string
  default     = "fifa-crawler"
}