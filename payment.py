# payment specific content 

paymenturi = 'http://wkst.example.com:9090/api/v1/query?query=sum%20by%20(user)%20(sum_over_time(s3_request_size_total%7Buser%3D%22<USER>%22%2C%20authority%3D~%22s3.example.com%22%2C%20region%3D~%22.*-1%22%7D%5B24h%5D)%20%2B%20sum_over_time(s3_request_total%7Buser%3D%22<USER>%22%2C%20authority%3D~%22s3.example.com%22%2C%20region%3D~%22.*-1%22%7D%5B24h%5D))%20*%200.00001&g0.tab=1&g0.display_mode=lines&g0.show_exemplars=0&g0.range_input=1h'

limit = 5000
