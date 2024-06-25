# Ceph global RGW Lab

This lab is for the SFP `Maximizing the Value of Your Rados Gateway with Ingress Strategies` for Cephalocon December 4th 2024.

The use cases that have been accessed are:

* Global access to RGW, independent of zones or regions.
* Rate limiting applied globally, encompassing all included zones, regions, and authorities.
* S3 metrics embedded within the request (no log parsing) across zones, regions, and authorities.
* Possible additional features to be utilized include:

# Requirements

This lab will be live-demonstrated. If you wish to run it independently, the following requirements must be fulfilled:

* 2 (Virtual) System CentOS 9 based 
	* min 4 Cores, 16GB memory
	* 3x 50GB Disks (1x system, 2x OSD) 
* 1 (Virtual) System CentOS 9 based
	* min 4 Cores, 8GB memory (depending on metrics storage duration)
	* 1x 50 GB Disk

# Envoy 
Envoy is an open source edge and service proxy, desgined for cloud-native applications. Most likely you have heard the name `envoy` in relation to Microservices and ServiceMesh.

We will utilize Envoy for its easy scalability, routing, and filtering capabilities. Specifically, we will leverage the external authorization feature 
to implement:

* Global rate limiting
* Global S3-specific metrics
* Global access with AWS_REGION-based routing decisions

# Open policy agent 
Policy-based control for cloud native environments. Flexible, fine-grained control for administrators across the stack.

The Open Policy Framework will be called by Envoy to implement policies, such as Role-Based Access Control (RBAC), rate limiting, and metrics 
collection through an API frontend to a Redis cluster.

# Redis and Frontend
A in-memory database for caching and streaming. 

The Flask API will serve as a frontend for making rate limit decisions and collecting metrics.

With Redis, we will have a centralized, fast storage solution for statistics used in rate limiting decisions. Although RGW does implement user and 
bucket rate limits, these are tied to a single daemon and are not shared between multiple daemons within one Ceph cluster.

Since the Open Policy Agent lacks out-of-the-box Redis integration, we instead utilize an HTTP(S) API. Furthermore, moving the Flask frontend 
functionality into OPA is crucial for reducing round-trip time (RTT).

## Use cases

**please ensure to follow the [Lab setup guide](#lab-setup-guide) prior continuing with this lab**.

### Global RGW access independent of Zone/Regions

Setting up the client environment

```
export AWS_EC2_METADATA_DISABLED=true
export AWS_ENDPOINT_URL=https://s3.example.com
export AWS_ACCESS_KEY_ID=user1
export AWS_SECRET_ACCESS_KEY=user1
export AWS_CA_BUNDLE=ca.crt
```

We should be able to connect to our RGW Clusters individually 

```
# cluster 1
AWS_ENDPOINT_URL=http://ceph1.example.com aws s3 ls  

# cluster 
AWS_ENDPOINT_URL=http://ceph2.example.com aws s3 ls 
```

We aim to utilize a single, globally accessible endpoint (e.g., s3.example.com) that benefits from the global or geo-distributed RGW clusters. To 
achieve this, we will skip traditional BGP and global load balancing approaches and instead use a DNS round-robin record to distribute traffic across 
our multiple RGW clusters.

```
# cluster 1
AWS_REGION=us-east-1 aws s3 ls 

# cluster 2
AWS_REGION=us-west-1 aws s3 ls 

# Checking with a User existing only in one region
export AWS_ACCESS_KEY_ID=user-east
export AWS_SECRET_ACCESS_KEY=user-east
AWS_REGION=us-east-1 aws s3 ls

# and failing on the other region accordingly
AWS_REGION=us-west-1 aws s3 ls
```

The Lab setup simplifies the process of selecting which endpoint to use, allowing you to specify a specific endpoint (e.g., Cluster 2) and still 
access resources from other clusters. While this approach introduces some latency as traffic passes from one cluster to another before reaching the 
client, it provides a convenient way to interact with multiple clusters without needing to manually determine which endpoint is best suited for each 
request.


#### hostname-style Bucket resolution

Currently, hostname bucket resolution requires manual configuration of used names and their assignment to corresponding clusters. This means that 
regex-based routing is not feasible in this scenario, which can lead to limitations in managing and scaling your RGW deployments. I am actively 
investigating ways to mitigate these limitations and provide a more flexible and scalable solution for hostname resolution.

### Global Rate limiting spawning all included Zone/Regions/Authorities

The lab includes two key components: a Redis deployment and an API frontend written in Python. 

I took steps to simplify maintenance by separating the code responsible for evaluating collected calls. This modular approach allows us to easily 
modify or overwrite specific parts of the code without having to rebuild the entire image repeatedly. 

The file is in the directory `app-src` and is named `rates.py` 
The main app will include any function defined in `rates.py` that starts with `rate_check_` and the function expectes three parameters `buckets` `app` `req` which will be provided by the main loop.

 * `buckets` is a tuple of `rates matched on` and the related values 
	 * rates matched on means (check the app for all combinations):
		 * region+user
		 * region+user+bucket
		 * region+user+bucket+source
		 * ... 
* `app` links the Flask methods in particular `logger` for debugging and notification output 
* `req` provides the actual values of:
	* region         # like us-east-1
	* user             # like user1-access-key-id
	* bucket.        # like user1
	* source         #  like 127.0.0.1 source of the AWS client
	*  method      # like GET/PUT/POST/HEAD/DELETE
	* authority     # S3 API endpoint fqdn


For this example, we'll configure a single rule to match specific criteria. The rule will be triggered when all of the following conditions are met:

* The authority is `s3.example.com`
* The user or bucket equals `user17`
* The requests per minute exceed 3

```
def rate_check_limit_fast(buckets, app, req):
    if not req.get("authority") == "s3.example.com":
        return True
    for bucket in buckets:
        app.logger.debug(f"check {req.get('authority')} bucket " +
                      f"{req.get('bucket')} user {req.get('user')} " +
                      f"req-count {bucket[1][min1]}")
        app.logger.debug(f"check bucket: {bucket[br]}")
        app.logger.debug(f"check bucket: {bucket[bv][min1]}")
        if not all([
                bucket[br].get("bucket") in ("*", req.get("bucket")),
                ]):
            continue
        if not all([
                req.get("bucket") in ("*", "user17"),
                req.get("user") == "user17",
                ]):
            continue
        if bucket[bv][min1] > 3:
            app.logger.info(f"Rate limiting {req}")
            app.logger.info(f"{bucket[bv]}")
            return False
    return True
```

We store the function in the `rates.py`file and restart the metrics deployment.
```
./run_metrics
```

To ensure that our rate limits are applied consistently, regardless of the S3 region being addressed, we'll verify our rule on all clusters.

```
export AWS_EC2_METADATA_DISABLED=true
export AWS_ENDPOINT_URL=https://s3.example.com
export AWS_ACCESS_KEY_ID=user17
export AWS_SECRET_ACCESS_KEY=user17
export AWS_CA_BUNDLE=ca.crt
export AWS_MAX_ATTEMPTS=1

# the first three requests are expected to pass successful
for x in $(seq 1 4) ; do 
    AWS_REGION=us-east-1 aws s3 ls 
done 

# output
#2024-06-09 08:37:04 user17
#2024-06-09 08:37:04 user17
#2024-06-09 08:37:04 user17
#An error occurred (429) when calling the ListBuckets operation: Too Many Requests

# the fourth call is expected to return Error 429 
# if we now switch the Region we should still receive 429 errors

for x in $(seq 1 4) ; do 
    AWS_REGION=us-west-1 aws s3 ls 
done 
# output
#An error occurred (429) when calling the ListBuckets operation: Too Many Requests
```

Now it's time to get creative! Let's configure some advanced rate limiting scenarios:

1. **User-specific GET requests**: Limit requests for user `user17` using the `GET` method.
2. **User-specific non-listing requests**: Restrict all methods (except listing buckets) for user `user17`.
3. **Region-specific DELETE requests**: Apply a separate limit for user `user17` using the `DELETE` method, but only in the `us-east-1` region.
4. **Global total request limit**: Set a global limit for all users across all regions.
5. **Time-of-day GET requests outside of business hours**: Enforce a separate limit for `GET` requests from all users outside of business hours (6pm 
to 6am).

These advanced configurations will allow us to fine-tune our rate limiting policies and provide more granular control over access to RGW clusters.


### global load balanced S3 

With our Lab setup, we've implemented a DNS RoundRobin to simulate global load balancing. This allows us to emulate a globally distributed system, 
where connections can be routed to the nearest available Ceph cluster for the region. As long as the Ceph cluster for the region is available, we're 
able to connect and retrieve content from anywhere in the world.

This configuration enables us to provide a seamless user experience, regardless of their location, by automatically routing requests to the closest 
available cluster.

```
# create some unique content in both Clusters
export AWS_ACCESS_KEY_ID=user1
export AWS_SECRET_ACCESS_KEY=user1

echo 'I am user1 zone us-east-1' | AWS_REGION=us-east-1 /usr/local/bin/aws s3 cp - s3://user1/content
echo 'I am user1 zone us-west-1' | AWS_REGION=us-west-1 /usr/local/bin/aws s3 cp - s3://user1/content
```

```
# we check which Envoy frontend we are connecting to by tcdumping the syn packets
tcpdump -nnNi any 'port 443 and (tcp[tcpflags] & (tcp-syn) != 0)' & 


# then we access the same Region/Bucket and see that we utilize a differnt Envoy in RoundRobin DNS manner

export AWS_ACCESS_KEY_ID=user1
export AWS_SECRET_ACCESS_KEY=user1

AWS_REGION=us-east-1 /usr/local/bin/aws s3 cp s3://user1/content - 

# output
#09:50:35.771401 eth0  Out IP 192.168.192.211.35954 > 192.168.192.129.443: Flags [S], seq 432983531, win 32120, options [mss 1460,sackOK,TS val 1200448334 ecr 0,nop,wscale 7], length 0
#09:50:35.772723 eth0  In  IP 192.168.192.129.443 > 192.168.192.211.35954: Flags [S.], seq 3019979653, ack 432983532, win 31856, options [mss 1460,sackOK,TS val 493905351 ecr 1200448334,nop,wscale 7], length 0
#I am user1 zone us-east-1

# AWS_REGION=us-east-1 /usr/local/bin/aws s3 cp s3://user1/content - 
#09:50:40.554645 eth0  Out IP 192.168.192.211.46880 > 192.168.192.155.443: Flags [S], seq 492105995, win 32120, options [mss 1460,sackOK,TS val 4192873898 ecr 0,nop,wscale 7], length 0
#09:50:40.557370 eth0  In  IP 192.168.192.155.443 > 192.168.192.211.46880: Flags [S.], seq 3694699857, ack 492105996, win 31856, options [mss 1460,sackOK,TS val 411404923 ecr 4192873898,nop,wscale 7], length 0
#I am user1 zone us-east-1
```

### global S3 specific metrics

Now that we've collected a range of metrics with our Lab setup, let's open a browser and explore the Prometheus UI interface. This will allow us to 
visualize and analyze the data we've collected, gaining valuable insights into the performance and behavior of our RGW clusters.

In the Prometheus UI, we can query the metrics we've collected and generate graphs, tables, or other visualizations to help us understand what's 
happening in our system.

Alternatively, you can access the metrics endpoint directly using a tool like `curl`

```
curl ceph1.example.com:8080/metrics
``` 

The metrics returned appear similar to the following format:

```
# HELP s3_request_total S3 Protocol request
# TYPE s3_request_total counter
s3_request_total{authority="s3.example.com",bucket="*",method="GET",region="us-west-1",source="192.168.192.208",user="user17"} 4.0
s3_request_total{authority="s3.example.com",bucket="*",method="GET",region="us-east-1",source="192.168.192.208",user="user17"} 4.0
# HELP s3_rate_limited_total S3 total rate limited requests
# TYPE s3_rate_limited_total counter
s3_rate_limited_total{authority="s3.example.com",bucket="*",method="GET",region="us-west-1",source="192.168.192.208",user="user17"} 4.0
s3_rate_limited_total{authority="s3.example.com",bucket="*",method="GET",region="us-east-1",source="192.168.192.208",user="user17"} 1.0
```


To further analyze the scraped metrics, you can execute a query using `jq`, a lightweight and flexible command-line JSON processor. For example, to 
extract the average request duration for all buckets in the `us-east-1` region.
The following query uses `jq` to:

* Select only the metrics with a region of `us-east-1`
* Extract the `request_duration_seconds` values
* Calculate the average (mean) value using the `mean` function

The output would be the average request duration for all buckets in the `us-east-1` region.

```
curl -ksg 'http://wkst.example.com:9090/api/v1/query?query=s3_request_total{}' | \
  jq -r '.data.result[] |
    select(.metric.authority=="s3.example.com") |
    [.metric.region, .metric.bucket, .metric.user,
     .metric.method, .value[1]] |
    join(" ") '

# output
#us-east-1 * user17 GET 4
#us-west-1 * user17 GET 4
```

Similar to analyze the rate limited metrics 

```
curl -ksg 'http://wkst.example.com:9090/api/v1/query?query=s3_rate_limited_total{}' | \
  jq -r '.data.result[] |
    select(.metric.authority=="s3.example.com") |
    [.metric.region, .metric.bucket, .metric.user,
     .metric.method, .value[1]] |
    join(" ") '

# output
#us-east-1 * user17 GET 1
#us-west-1 * user17 GET 4
```

### Payment/finops use-case 

In addition to exploring the technical aspects of our Lab setup, we can also delve into financial operations and payment limitations. By using our 
rate limiting capabilities, we can create custom pricing plans for our customers, ensuring that their usage aligns with their budget.

For example, we could set a daily limit on the number of requests or data transferred, thereby controlling costs and preventing unexpected overages. 
This would be particularly useful for businesses that require predictable expenses and budgeting.

By integrating financial operations and payment limitations into our Lab setup, we can provide a more comprehensive and customer-centric solution, 
helping to drive revenue and growth for our business.

To test the payment limitations, let's update the `payment.py` file by changing the `limit` value to 0.0001. This will simulate a payment limit that can 
be reached relatively quickly.

By setting the `limit` to 0.0001, we'll be able to see how our system responds when a customer reaches their payment limit and needs to make a new payment 
to continue using our services.


```
# update on both clusters
sed -i -e ' s#limit = 5000#limit = 0.0001#; ' payment.py 
```  

By restarting the metrics endpoint, we can ensure that any changes we've made to the code are reflected in the data being collected and visualized.

```
# restart on both clusters
./run_metrics
```

To simulate a scenario where we reach the payment limit, let's iterate 50 requests. For the purpose of this lab, it doesn't matter if these requests 
are actually valid or not - what matters is that they are not rate-limited requests.

```
export AWS_ACCESS_KEY_ID=user1
export AWS_SECRET_ACCESS_KEY=user1

for x in $(seq 1 50); do 
    for region in us-east-1 us-west-1 ; do 
      AWS_REGION=${region} /usr/local/bin/aws s3 cp s3://user1/content -
    done
done 

# output
#I am user1 zone us-west-1
#I am user1 zone us-east-1
#download failed: s3://user1/content to - An error occurred (402) when calling the GetObject operation (reached max retries: 0): Payment Required
#download failed: s3://user1/content to - An error occurred (402) when calling the HeadObject operation (reached max retries: 0): Payment Required

```

### Conclusion of possiple additional features to be utilized

**Potential Enhancements**

Despite some limitations in our setup, by using Envoy as a frontend and introducing additional 
daemons, we can enhance RGW with functionality not currently available in Ceph.

One of the most impressive aspects of our setup is the ability to seamlessly switch between multiple clusters based on a single parameter - region. 
This allows us to dynamically route content and provide a high level of availability and scalability.

**Benefits of Envoy**

While there is some overhead associated with introducing Envoy as a frontend, I believe it's well worth the benefits we gain. For example:

* Outlier detection: automatically bringing RGW instances online or taking them offline as needed
* Persistent connections: reducing the need for handshakes and improving overall performance
* Dynamic configuration: simplifying scaling and reducing the need to reload/redeploy configurations

**Additional Features**

I'm also excited about some of the additional features we could implement, such as:

* Time-based access or rejection: allowing us to limit updates during certain times of day or temporarily disable all updates for maintenance
* Cluster-level maintenance: allowing us to take a cluster offline for maintenance without affecting overall availability

These are just a few ideas, but I believe there are many more opportunities to enhance RGW and provide even more value to users.

Take a look at some [screenshots](Dashboards-Routing.md) showcasing various use cases for visualizing and routing traffic within the lab.

#####  Lab setup guide

###### Setup the Workstation instance as it will provide DNS for our Lab

* Workstation preparation

``` 
# install dependencies
dnf install podman dnsmasq unzip bind-utils -y

# install aws-cli
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
ln -s /usr/local/bin/aws /usr/bin/aws
``` 

* configure dnsmasq for the Lab

```
mkdir /etc/dnsmasq.d/hosts
cat <<'EOF' > /etc/dnsmasq.d/lab.conf
no-resolv
strict-order
domain=example.com
server=8.8.8.8
interface=*
hostsdir=/etc/dnsmasq.d/hosts
EOF

export IP1=<ip-of-ceph1>
export IP2=<ip-of-ceph2>
export IP3=<ip-of-wkst>

cat <<EOF > /etc/dnsmasq.d/hosts/lab
${IP1} s3.example.com ceph1.example.com
${IP2} s3.example.com ceph2.example.com
${IP3} wkst.example.com
EOF

systemctl enable --now dnsmasq
```

* verify the names by pinging each record

```
# -W1 sets a timeout of 1sec if you have not started all VM's
ping -W1 -c1 ceph1.example.com

ping -W1 -c1 ceph2.example.com

ping -W1 -c1 wkst.example.com

ping -W1 -c1 s3.example.com
```

###### Boot strapping the Ceph Single node instances

* Ceph bootstrap preparation

```
# install quincy release 
dnf install centos-release-ceph-quincy -y

# install dependencies
dnf install --enablerepo=centos-ceph-quincy cephadm podman dnsmasq unzip bind-utils git -y

# create cephadmin unprivileged user 
useradd -G wheel cephadmin

# enable password less sudo
sed -i -e " s#^%wheel.*#%wheel     ALL=(ALL)       NOPASSWD: ALL#; " /etc/sudoers

# create ssh key for cephadm deployment
runuser -u cephadmin -- ssh-keygen -N '' -f /home/cephadmin/.ssh/id_rsa

# install aws-cli
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
ln -s /usr/local/bin/aws /usr/bin/aws
``` 

* set the Region and Zones for the lab (the second zone is just for service identification)

```
export RGWREGION=us
export RGWZONE=us-east-1
export RGWZONE2=us-east-2
export RGWPORT2=81
```

* adjust the block device list for the two OSD's according to your setup

    * in this lab we have vdb and vdc with 50G to be used

    ``` 
    lsblk

    # output
    vda                                                           252:0    0   50G  0 disk 
    `-vda1                                                        252:1    0   50G  0 part /rootfs
    vdb                                                           252:16   0   50G  0 disk 
    vdc                                                           252:32   0   50G  0 disk 
    vdd                                                           252:48   0  364K  1 disk 
    ```

    * update the rollout-tmpl.yml accordingly

    ```
    vi rollout-tmpl.yml

    # update the OSD spec to
    ---
    service_type: osd
    service_id: default_osd_group
    placement:
      hosts:
        - ${RGWHOST}
    data_devices:
      paths:
        - /dev/vdb    # <<< first device
        - /dev/vdc    # <<< second device
    ```

* execute the bootstrap process

```
sh bootstrap.sh 
```

* you should now have a working Single Node Ceph Cluster
* verify that the Cluster is `HEALTHY` prior progressing

```
cephadm shell -v /root:/tmp 
ceph -s
```

* setup the `us-east-1` zone 

```
export RGWREGION=us
export RGWZONE=us-east-1
export RGWMASTER=ceph1
export RGWZONE2=us-east-2

sh /tmp/zone-boostrap-primary.sh 

# restart the second RGW instance as it's only used in this lab
ceph orch restart rgw.default.us-east-2 
``` 

* check that RGW instances are up and running

```
ceph orch ls 
ceph orch ps --daemon_type rgw
```

* repeat the steps for the second instance with following env variables

```
for boot strapping
export RGWREGION=us
export RGWZONE=us-west-1
export RGWZONE2=us-west-2
export RGWPORT2=81

# for zone setup
export RGWREGION=us
export RGWZONE=us-west-1
export RGWZONE2=us-west-2
export RGWMASTER=ceph2
```

###### Adding Users and Buckets to operate on

* On Ceph cluster us-east-1 execute following to create 50 users

```
cephadm shell -v /root:/tmp
export RGWREALM=us
export RGWZONE=us-east-1
/tmp/create_users

u='-east'
/usr/bin/radosgw-admin user create --uid=user${u} \
      --display-name=user${u} \
      --access-key=user${u} \
      --secret-key=user${u} \
      --rgw-zone=${RGWZONE} \
      --rgw-realm=${RGWREALM}
```

* On Ceph cluster us-west-1 execute following to create 50 users

```
cephadm shell -v /root:/tmp
export RGWREALM=us
export RGWZONE=us-west-1
/tmp/create_users

u='-west'
/usr/bin/radosgw-admin user create --uid=user${u} \
      --display-name=user${u} \
      --access-key=user${u} \
      --secret-key=user${u} \
      --rgw-zone=${RGWZONE} \
      --rgw-realm=${RGWREALM}
```

* On the Workstation execute following to create the buckets on both Clusters accordingly

```
./create_buckets
```

###### Adding Envoy as frontend

* create the envoy config by executing `create_config.sh` in the tmpl directory.

```
cd tmpl
./create_config.sh

# if you are using the names from the lab, you can hit enter for all inputs
# Region1 Name(us-east-1): 
# Region2 Name(us-west-1): 
# S3 Endpoint Port(443): 
# S3 Endpoint fqdn(s3.example.com): 
# RGW (us-east-1) endpoint(ceph1.example.com): 
# RGW (us-west-1) endpoint(ceph2.example.com): 
# OpenPolicyAgent (all) endpoint(wkst.example.com): 
# RGW (all) endpoint port1(80): 
# RGW (all) endpoint port2(81): 
# RGW (all) dashboard port(8443): 
# OpenPolicyAgent (all) port(9191): 

cd ..
```

* create the config and the cert directory for envoy

```
mkdir certs config 
```

* copy the certificates and the generated config into the directories

```
cp tls.crt tls.key certs/
cp tmpl/envoy-config.yaml config/
chcon -t container_file_t -R certs config
```

* startup envoy by executing `run_envoy` 

```
./run_envoy
```

###### Adding OpenPolicyAgent as authorization framework

OpenPolicyAgent is configured by writing `rego`. The Policy in this lab will handle Rate limiting checks and Payment checks through an http call to the metrics frontend.

* startup openpolicyagent by executing `run_opa` 

```
chcon -t container_file_t policy.rego
./run_opa
```

###### Adding python-flask metrics frontend 

The Flask-Python framework provides us with a lightweight and flexible way to create an HTTP-based API that can be easily integrated with Envoy. We 
can use Flask's built-in support for routing and request handling to create a simple and effective authorization service.

The python code comes with to files taking parameters and functions to POC extend the functionality.

* ensure the python code is valid and the SELinux context is set accordingly

```
# both command should succeed without any error shown
python rates.py
python payment.py 

chcon -t container_file_t *.py
``` 

* start the metrics service by executing `run_metrics` 

```
./run_metrics
``` 

###### Adding backends for metrics and limits

Since we want to have global data for metrics and payment, we simulate a centralized Redis and Prometheus backend by running the services on the workstation of the lab.

```
./run_redis
chcon -t container_file_t prometheus.yml
./run_prometheus
``` 


