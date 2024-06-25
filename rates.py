# buckets is an array of tuples where item[0] is counter matches
#                                     item[1] is the counter values
# [ (dict
# define bucket name to values
min1, min2, min5, min15, min30 = 1, 2, 5, 15, 30
br, bv = 0, 1

def dis_rate_check_global(buckets):
    if any(
        [
            sum(buckets.values()) < -1,
            buckets[min1] < -1,
            buckets[min2] < -1,
            buckets[min5] < -1,
            buckets[min15] < -1,
            buckets[min30] < -1,
        ]
    ):
        return False
    return True

def dis_rate_check_limit_fast(buckets, app):
    for bucket in buckets:
        app.logger.debug(f"check bucket {bucket[1][min1]}")
        if bucket[0].get("source") != "192.168.192.14":
            continue
        if bucket[1][min1] > 3:
            return False
    return True


def rate_check_limit_fast(buckets, app, req):
    if not req.get("authority") == "s3.example.com":
        return True
    for bucket in buckets:
        app.logger.error(f"check {req.get('authority')} bucket {req.get('bucket')}" + 
               f" user {req.get('user')} req-count {bucket[1][min1]} bv {bucket[bv]}")
        app.logger.error(f"check bucket: {bucket[br]}")
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
            return False
    return True

