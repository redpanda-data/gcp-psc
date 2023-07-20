package cloud_dns

//func Test() {
//	handler, err := New("paul-wilkinson-381610", "private-zone", "rp-locator.json")
//	if err != nil {
//		os.Exit(1)
//	}
//
//	ip, err := handler.LookupARecord("foo.cihueamrbdersm5f2h80.byoc.prd.cloud.redpanda.com.")
//	assert.Equal(nil, ip, "", "Lookup on a non-existent hostname should result in an empty string")
//	assert.NotNil(nil, err, "Lookup on a non-existent hostname should result in an error")
//
//	err = handler.CreateARecord("foo.cihueamrbdersm5f2h80.byoc.prd.cloud.redpanda.com", "1.1.1.1")
//	assert.Nil(nil, err, "Successfully creating a record should not result in an error")
//
//	err = handler.CreateARecord("foo.cihueamrbdersm5f2h80.byoc.prd.cloud.redpanda.com", "1.1.1.2")
//	assert.NotNil(nil, err, "Creating a record that already exists should result in an error")
//
//	ip, err = handler.LookupARecord("foo.cihueamrbdersm5f2h80.byoc.prd.cloud.redpanda.com.")
//	assert.NotNil(nil, ip, "Lookup on a hostname that exists should result in an ip address")
//	assert.Nil(nil, err, "Lookup on a hostname that exists should not result in an error")
//
//	err = handler.DeleteARecord("foo.cihueamrbdersm5f2h80.byoc.prd.cloud.redpanda.com.", "1.1.1.1")
//	assert.Nil(nil, err, "Deleting a record that exists should not result in an error")
//
//	err = handler.DeleteARecord("foo.cihueamrbdersm5f2h80.byoc.prd.cloud.redpanda.com.", "1.1.1.1")
//	assert.NotNil(nil, err, "Deleting a record that doesn't exist should result in an error")
//
//	ip, err = handler.LookupARecord("foo.cihueamrbdersm5f2h80.byoc.prd.cloud.redpanda.com.")
//	assert.Equal(nil, ip, "", "Lookup on a non-existent hostname should result in an empty string")
//	assert.NotNil(nil, err, "Lookup on a non-existent hostname should result in an error")
//
//	handler.LookupAllARecords("kafka")
//}
