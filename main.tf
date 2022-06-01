provider "aws" {
   region = "us-east-1"
}

resource "aws_instance" "example" {
   ami = "ami-0022f774911c1d690"
   instance_type = "t2.micro"
   
   tags = {
       Name = "terraform-example"
   }
}