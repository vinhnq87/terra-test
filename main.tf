provider "aws" {
    region = "us-east-1"
}

data "aws_vpc" "default" {
    default = true
}

data "aws_subnet_ids" "default" {
    vpc_id = data.aws_vpc.default.id
}

variable "server_port" {
    description = "port server use for http request"
    type = number
    default = 80
}

resource "aws_s3_bucket" "terraform_state" {
    bucket = "test2-stg-tf-state"
    
    lifecycle {
        prevent_destroy = true
    }
    
    versioning {
        enabled = true
    }
    
    server_side_encryption_configuration {
        rule {
            apply_server_side_encryption_by_default {
                sse_algorithm = "AES256"
            }
        }
    }
} 

resource "aws_dynamodb_table" "terraform_locks" {
    name = "test2-stg-tf-locks"
    billing_mode = "PAY_PER_REQUEST"
    hash_key = "LockID"
    
    attribute {
        name = "LockID"
        type = "S"
    }
}

terraform {
    backend "s3" {
        bucket = "test2-stg-tf-state"
        key = "terraform.tfstate"
        region = "us-east-1"
        dynamodb_table = "test2-stg-tf-locks"
        encrypt = true
    }
}


resource "aws_security_group" "alb" {
    name = "terraform-example-alb"
    
    ingress {
        from_port = 80
        to_port = 80
        protocol ="tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    
    egress {
        from_port = 0
        to_port = 0
        protocol ="-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
    
    lifecycle {
        create_before_destroy = true
    }
}

resource "aws_launch_configuration" "example" {
    image_id = "ami-052efd3df9dad4825"
    instance_type = "t2.micro"
    security_groups = [aws_security_group.alb.id]
    user_data = <<-EOF
                #!/bin/bash
                echo "Hello, world" > index.html
                nohup busybox httpd -f -p ${var.server_port} &
                EOF
    
    lifecycle {
        create_before_destroy = true
    }
}

resource "aws_lb" "example" {
    name = "terraform-asg-example"
    load_balancer_type = "application"
    subnets = data.aws_subnet_ids.default.ids
    security_groups = [aws_security_group.alb.id]
}

resource "aws_lb_listener" "http" {
    load_balancer_arn = aws_lb.example.arn
    port = 80
    protocol = "HTTP"
    
    default_action {
        type = "fixed-response"
        
        fixed_response {
          content_type = "text/plain"
          message_body = "404: page not found"
          status_code = 404
          }
    }
}

resource "aws_lb_target_group" "asg" {
    name = "terraform-asg-example"
    port = var.server_port
    protocol = "HTTP"
    vpc_id = data.aws_vpc.default.id
    
    health_check {
        path = "/"
        protocol = "HTTP"
        matcher= "200"
        interval =15
        timeout= 3
        healthy_threshold =2
        unhealthy_threshold = 2
    }
    
    lifecycle {
        create_before_destroy = true
    }
}

resource "aws_autoscaling_group" "example" {
    launch_configuration = aws_launch_configuration.example.name
    vpc_zone_identifier = data.aws_subnet_ids.default.ids
    
    target_group_arns = [aws_lb_target_group.asg.arn]
    health_check_type = "ELB"
    
    min_size = 2
    max_size = 10
    
    tag {
        key = "Name"
        value = "terraform-asg-example"
        propagate_at_launch = true
    }
}

resource "aws_lb_listener_rule" "asg"{
    listener_arn = aws_lb_listener.http.arn
    priority = 100
    
    condition {
        path_pattern {
            values = ["*"]
        }
    }
    
    action {
        type = "forward"
        target_group_arn = aws_lb_target_group.asg.arn
    }
}


output "alb_dns_name" {
    value = aws_lb.example.dns_name
    description = "domain name of LB"
}

