variable "region" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "us-east-1"
}

variable "glue_database_name" {
  description = "The name of the Glue database"
  type        = string
  default     = "incremental_load_db"
}

variable "glue_table_name" {
  description = "The name of the Glue table"
  type        = string
  default     = "incremental_load_table"
}

variable "glue_crawler_name" {
  description = "The name of the Glue crawler"
  type        = string
  default     = "incremental_load_crawler"
}