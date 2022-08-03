provider "aws" {
    region = "us-east-1"
}

resource "aws_instance" "example" {
    ami = "ami-052efd3df9dad4825"   //ubuntu
    instance_type = "t2.micro"
    
    tags = {
        Name = "terraform-example"
    }
}