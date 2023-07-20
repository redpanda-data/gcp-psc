output "seed" {
  value = "${trimsuffix(google_dns_record_set.seed.name,".")}:30092"
}