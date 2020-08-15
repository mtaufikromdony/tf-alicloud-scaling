resource "alicloud_vpc" "default" {
  name       = "web-vpc"
  cidr_block = "172.20.0.0/22"
}

resource "alicloud_vswitch" "default" {
  vpc_id            = alicloud_vpc.default.id
  cidr_block        = "172.20.1.0/24"
  availability_zone = var.zone
}

resource "alicloud_security_group" "sec-group" {
  name                = "web-sg"
  vpc_id              = alicloud_vpc.default.id
  # Allow instances in the same security group reaching each other
  inner_access_policy = "Accept"
}

resource "alicloud_security_group_rule" "allow_ssh" {
  # Refer the security group ID
  security_group_id = alicloud_security_group.sec-group.id
  type              = var.type
  ip_protocol       = "tcp"
  # Since the security group is for using in the VPC, you need to set it to intranet: https://www.terraform.io/docs/providers/alicloud/r/security_group_rule.html
  nic_type          = "intranet"
  policy            = "accept"
  cidr_ip           = "0.0.0.0/0"
  port_range        = "22/22"
}

resource "alicloud_security_group_rule" "allow_http" {
  # Refer the security group ID
  security_group_id = alicloud_security_group.sec-group.id
  type              = var.type
  ip_protocol       = "tcp"
  # Since the security group is for using in the VPC, you need to set it to intranet: https://www.terraform.io/docs/providers/alicloud/r/security_group_rule.html
  nic_type          = "intranet"
  policy            = "accept"
  cidr_ip           = "0.0.0.0/0"
  port_range        = "80/80"
}

resource "alicloud_key_pair" "taufik-key" {
  key_name       = "cloud.key"
  public_key = "ssh-rsa ...."
}

resource "alicloud_security_group_rule" "allow_all_tcp" {
  type              = var.type
  ip_protocol       = "tcp"
  nic_type          = "intranet"
  policy            = "accept"
  port_range        = "1/65535"
  priority          = 1
  security_group_id = alicloud_security_group.sec-group.id
  cidr_ip           = "0.0.0.0/0"
}

resource "alicloud_slb" "slb" {
  name       = "-web-slb-tf"
  vswitch_id = alicloud_vswitch.default.id
  address_type = "internet"
}

resource "alicloud_slb_listener" "http" {
  load_balancer_id = alicloud_slb.slb.id
  backend_port = 80
  frontend_port = 80
  bandwidth = 10
  protocol = "http"
  health_check="on"
  health_check_type = "http"
  health_check_connect_port = 80
}

output "slb_public_ip"{
  value = "${alicloud_slb.slb.address}"
}

resource "alicloud_ess_scaling_group" "scaling" {
  min_size = 1
  max_size = 3
  scaling_group_name = "tf-scaling-web"
  vswitch_ids=["${alicloud_vswitch.default.id}"]
  loadbalancer_ids = ["${alicloud_slb.slb.id}"]
  removal_policies   = ["OldestInstance", "NewestInstance"]
  depends_on = ["alicloud_slb_listener.http"]
}

resource "alicloud_ess_scaling_configuration" "config" {
  scaling_group_id = "${alicloud_ess_scaling_group.scaling.id}"
  image_id = "ubuntu_18_04_x64_20G_alibase_20200618.vhd"
  instance_type = var.instance_type 
  security_group_id = "${alicloud_security_group.sec-group.id}"
  active=true
  enable=true
  key_name = alicloud_key_pair.taufik-key.key_name
  user_data = "#!/bin/sh\napt update\napt install apache2 php -y\nservice apache2 start\ncd /var/www/html\nwget https://taufik2020-oss.oss-ap-southeast-5.aliyuncs.com/archive-web.tar.gz\ntar -xzvf archive-web.tar.gz\nrm -f index.html"
  internet_max_bandwidth_in=10
  internet_max_bandwidth_out= 10
  internet_charge_type = "PayByTraffic"
  force_delete= true

}

# ---------------
# Scaling rules & alarms
# ---------------
resource "alicloud_ess_scaling_rule" "add-instance" {
  scaling_group_id = "${alicloud_ess_scaling_group.scaling.id}"
  adjustment_type  = "QuantityChangeInCapacity"
  adjustment_value = 1
}

resource "alicloud_ess_scaling_rule" "remove-instance" {
  scaling_group_id = "${alicloud_ess_scaling_group.scaling.id}"
  adjustment_type  = "QuantityChangeInCapacity"
  adjustment_value = -1
}

resource "alicloud_ess_alarm" "alarm-1-add-instance" {
  name                = "alarm-1-add-instance"
  description         = "Add 1 instance when CPU usage >70%"
  alarm_actions       = [alicloud_ess_scaling_rule.add-instance.ari]
  scaling_group_id = "${alicloud_ess_scaling_group.scaling.id}"
  metric_type         = "system"
  metric_name         = "CpuUtilization"
  period              = 60
  statistics          = "Average"
  threshold           = 70
  comparison_operator = ">="
  evaluation_count    = 2
}

resource "alicloud_ess_alarm" "alarm-2-remove-instance" {
  name                = "alarm-2-remove-instance"
  description         = "Remove 1 instance when CPU usage <10%"
  alarm_actions       = [alicloud_ess_scaling_rule.remove-instance.ari]
  scaling_group_id = "${alicloud_ess_scaling_group.scaling.id}"
  metric_type         = "system"
  metric_name         = "CpuUtilization"
  period              = 60
  statistics          = "Average"
  threshold           = 10
  comparison_operator = "<="
  evaluation_count    = 2
}