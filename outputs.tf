output "public_ip" {
  value = aws_instance.minecraft_server.public_ip
}

output "minecraft_connect" {
  value = "Connect to the Minecraft server at: ${aws_instance.minecraft_server.public_ip}:25565"
}

output "ssh_command" {
  value = "ssh -i minecraft_key.pem ubuntu@${aws_instance.minecraft_server.public_ip}"
}