package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

// The fixtures below are synthetic: made-up IDs, documentation addresses, no
// controller dump (CONTEXT.md Q25/Q30).

func mustObj(t *testing.T, s string) obj {
	t.Helper()
	var o obj
	if err := json.Unmarshal([]byte(s), &o); err != nil {
		t.Fatal(err)
	}
	return o
}

func testState(t *testing.T) *State {
	t.Helper()
	return &State{
		Names: Names{
			Zones:    map[string]string{"Internal": "z-int", "External": "z-ext"},
			Networks: map[string]string{"Media": "n-media", "IoT": "n-iot"},
			Lists:    map[string]string{"Scanners": "l-scan"},
		},
		Zones: []obj{
			mustObj(t, `{"id":"z-int","name":"Internal","networkIds":[]}`),
			mustObj(t, `{"id":"z-ext","name":"External","networkIds":[]}`),
		},
		Lists: []obj{mustObj(t, `{"id":"l-scan","name":"Scanners","type":"IPV4_ADDRESSES","items":[{"type":"SUBNET","value":"192.0.2.0/24"},{"type":"IP_ADDRESS","value":"198.51.100.7"}]}`)},
		Policies: []obj{
			mustObj(t, `{"id":"p-allow","name":"allow","enabled":true,"index":10000,"reportFlowEnabled":true,"metadata":{"origin":"USER_DEFINED"},
				"action":{"type":"ALLOW","allowReturnTraffic":true},
				"source":{"zoneId":"z-int","trafficFilter":{"type":"NETWORK","networkFilter":{"networkIds":["n-media"],"matchOpposite":false}}},
				"destination":{"zoneId":"z-ext","trafficFilter":{"type":"PORT","portFilter":{"type":"PORTS","matchOpposite":false,"items":[{"type":"PORT_NUMBER","value":16021},{"type":"PORT_NUMBER","value":6517}]}}},
				"ipProtocolScope":{"ipVersion":"IPV4"},"loggingEnabled":false}`),
			mustObj(t, `{"id":"p-block","name":"block","enabled":true,"description":"","metadata":{"origin":"USER_DEFINED"},
				"action":{"type":"BLOCK"},
				"source":{"zoneId":"z-int","trafficFilter":{"type":"IP_ADDRESS","ipAddressFilter":{"type":"TRAFFIC_MATCHING_LIST","matchOpposite":false,"trafficMatchingListId":"l-scan"}}},
				"destination":{"zoneId":"z-ext"},"ipProtocolScope":{"ipVersion":"IPV4"},"loggingEnabled":false}`),
		},
		Orders:                map[[2]string]Ordering{{"z-int", "z-ext"}: {Before: []string{"p-allow", "p-block", "p-other"}, After: []string{}}},
		MDNS:                  mustObj(t, `{"_id":"m","key":"mdns","mode":"all","enabled_for_network_ids":["c-media","c-iot"]}`),
		ClassicNetworks:       map[string]string{"Media": "c-media", "IoT": "c-iot"},
		ClassicSettings:       map[string]obj{},
		ClassicNetworksByName: map[string]obj{},
		WLANs:                 map[string]obj{},
		Devices:               map[string]obj{},
	}
}

func testDecl(t *testing.T) *Declarations {
	t.Helper()
	return &Declarations{
		// Same content as testState, written the way unifi/controller/ is:
		// names instead of IDs, ports and list items in a different order.
		Policies: []obj{
			mustObj(t, `{"name":"allow","enabled":true,"action":{"type":"ALLOW","allowReturnTraffic":true},
				"source":{"zone":"Internal","trafficFilter":{"type":"NETWORK","networkFilter":{"networks":["Media"],"matchOpposite":false}}},
				"destination":{"zone":"External","trafficFilter":{"type":"PORT","portFilter":{"type":"PORTS","matchOpposite":false,"items":[{"type":"PORT_NUMBER","value":6517},{"type":"PORT_NUMBER","value":16021}]}}},
				"ipProtocolScope":{"ipVersion":"IPV4"},"loggingEnabled":false}`),
			mustObj(t, `{"name":"block","enabled":true,"action":{"type":"BLOCK"},
				"source":{"zone":"Internal","trafficFilter":{"type":"IP_ADDRESS","ipAddressFilter":{"type":"TRAFFIC_MATCHING_LIST","matchOpposite":false,"trafficMatchingList":"Scanners"}}},
				"destination":{"zone":"External"},"ipProtocolScope":{"ipVersion":"IPV4"},"loggingEnabled":false}`),
		},
		Lists: []obj{mustObj(t, `{"name":"Scanners","type":"IPV4_ADDRESSES","items":[{"type":"IP_ADDRESS","value":"198.51.100.7"},{"type":"SUBNET","value":"192.0.2.0/24"}]}`)},
		MDNS:  MDNSDecl{Mode: "all", Networks: []string{"IoT", "Media"}},
	}
}

func TestBuildPlanNoChanges(t *testing.T) {
	p, err := buildPlan(testDecl(t), testState(t))
	if err != nil {
		t.Fatal(err)
	}
	if !p.Empty() {
		var b strings.Builder
		p.Print(&b)
		t.Fatalf("want no changes (array order, missing description and controller-owned fields must not count), got:\n%s", b.String())
	}
}

func TestBuildPlanUpdateAndCreate(t *testing.T) {
	d := testDecl(t)
	d.Policies[0]["enabled"] = false
	d.Lists[0]["items"] = []any{obj{"type": "IP_ADDRESS", "value": "203.0.113.9"}}
	d.Policies = append([]obj{mustObj(t, `{"name":"new","enabled":true,"action":{"type":"BLOCK"},
		"source":{"zone":"Internal"},"destination":{"zone":"External"},"ipProtocolScope":{"ipVersion":"IPV6"},"loggingEnabled":false}`)}, d.Policies...)
	p, err := buildPlan(d, testState(t))
	if err != nil {
		t.Fatal(err)
	}
	if len(p.Lists) != 1 || p.Lists[0].ID != "l-scan" || !slices.Equal(p.Lists[0].Paths, []string{"items"}) {
		t.Errorf("list change = %+v", p.Lists)
	}
	if len(p.Policies) != 2 || p.Policies[0].ID != "" || p.Policies[1].ID != "p-allow" || !slices.Equal(p.Policies[1].Paths, []string{"enabled"}) {
		t.Errorf("policy changes = %+v", p.Policies)
	}
	if len(p.Orders) != 1 {
		t.Fatalf("orders = %+v", p.Orders)
	}
	want := []string{newPrefix + policyKey("new", "Internal", "External"), "p-allow", "p-block", "p-other"}
	if got := p.Orders[0].Desired.Before; !slices.Equal(got, want) {
		t.Errorf("desired order = %v, want %v", got, want)
	}
}

func TestBuildPlanCreateListResolvesPlaceholder(t *testing.T) {
	s := testState(t)
	s.Lists, s.Names.Lists = nil, map[string]string{}
	s.Policies = s.Policies[:1]
	p, err := buildPlan(testDecl(t), s)
	if err != nil {
		t.Fatal(err)
	}
	if len(p.Lists) != 1 || p.Lists[0].ID != "" {
		t.Fatalf("lists = %+v", p.Lists)
	}
	if len(p.Policies) != 1 || p.Policies[0].ID != "" {
		t.Fatalf("policies = %+v", p.Policies)
	}
	b := encode(p.Policies[0].Body)
	if !strings.Contains(b, `"trafficMatchingListId":"`+newPrefix+`Scanners"`) || strings.Contains(b, `"zone"`) {
		t.Errorf("unresolved body: %s", b)
	}
}

func TestBuildPlanZonesAndAbsentPolicies(t *testing.T) {
	d := testDecl(t)
	d.Zones = []ZoneDecl{{Name: "IoT", Networks: []string{"IoT"}}}
	d.Policies = append(d.Policies, mustObj(t, `{"name":"iot-block","enabled":true,"action":{"type":"BLOCK"},
		"source":{"zone":"IoT"},"destination":{"zone":"External"},"ipProtocolScope":{"ipVersion":"IPV4"},"loggingEnabled":false}`))
	d.AbsentPolicies = []obj{mustObj(t, `{"name":"block","source":{"zone":"Internal"},"destination":{"zone":"External"}}`)}
	// Remove "block" from desired Policies so validate() allows it in AbsentPolicies.
	d.Policies = append(d.Policies[:1], d.Policies[2:]...)

	s := testState(t)
	p, err := buildPlan(d, s)
	if err != nil {
		t.Fatal(err)
	}
	if len(p.Zones) != 1 || p.Zones[0].ID != "" {
		t.Fatalf("zones = %+v", p.Zones)
	}
	if len(p.DeletePolicies) != 1 || p.DeletePolicies[0].ID != "p-block" {
		t.Fatalf("deletePolicies = %+v", p.DeletePolicies)
	}
	for _, ord := range p.Orders {
		if slices.Contains(ord.Desired.Before, "p-block") {
			t.Errorf("deleted policy p-block leaked into desired order: %v", ord.Desired.Before)
		}
	}
}

func TestBuildPlanSettingsAndDevices(t *testing.T) {
	d := testDecl(t)
	d.Settings = SettingsDecl{
		Settings: map[string]obj{
			"igmp_snooping": {
				"networks":                []any{"Media", "IoT"},
				"fastleave_networks":      []any{"IoT"},
				"primary_querier_device":  "CoreSW",
				"failover_querier_device": "EdgeSW",
			},
			"radius": {"enabled": false},
		},
		Networks: map[string]obj{
			"Media": {"dhcpd_leasetime": float64(86400)},
		},
		WLANs: map[string]obj{
			"home": {"roaming_assistant_na_rssi": float64(-68)},
		},
		Devices: map[string]obj{
			"EdgeSW": {
				"flowctrl_enabled": false,
				"config_network":   obj{"dns1": "10.0.0.1"},
				"port_overrides": []any{
					obj{"port_idx": float64(1), "name": "Uplink", "autoneg": true, "unset": []any{"speed", "full_duplex"}},
				},
			},
			"AP1": {
				"bandsteering_mode": "off",
				"radio_overrides": []any{
					obj{"radio": "na", "min_rssi_enabled": true, "min_rssi": float64(-72)},
				},
			},
		},
	}

	s := testState(t)
	s.ClassicSettings["igmp_snooping"] = mustObj(t, `{"_id":"s-igmp","key":"igmp_snooping","network_ids":["c-media"],"fastleave_for_network_ids":["c-iot"],"primary_querier":"aa:aa:aa:aa:aa:01","failover_querier":""}`)
	s.ClassicSettings["radius"] = mustObj(t, `{"_id":"s-rad","key":"radius","enabled":false,"x_secret":"keep-me"}`)
	s.ClassicNetworksByName["Media"] = mustObj(t, `{"_id":"c-media","name":"Media","dhcpd_leasetime":7200}`)
	s.WLANs["home"] = mustObj(t, `{"_id":"w-home","name":"home","roaming_assistant_na_rssi":-60,"x_passphrase":"psk"}`)
	s.Devices["CoreSW"] = mustObj(t, `{"_id":"d-core","name":"CoreSW","mac":"aa:aa:aa:aa:aa:01"}`)
	s.Devices["EdgeSW"] = mustObj(t, `{
		"_id":"d-edge","name":"EdgeSW","mac":"aa:aa:aa:aa:aa:02","flowctrl_enabled":true,
		"config_network":{"ip":"10.0.0.3","dns1":"1.1.1.1"},
		"port_overrides":[{"port_idx":1,"name":"Old","autoneg":false,"speed":1000,"full_duplex":true},{"port_idx":2,"name":"P2"}]
	}`)
	s.Devices["AP1"] = mustObj(t, `{
		"_id":"d-ap1","name":"AP1","mac":"aa:aa:aa:aa:aa:03","bandsteering_mode":"prefer_5g",
		"radio_table":[
			{"radio":"ng","name":"wifi0","min_rssi_enabled":false,"min_rssi":-72},
			{"radio":"na","name":"wifi1","min_rssi_enabled":true,"min_rssi":-67}
		]
	}`)

	p, err := buildPlan(d, s)
	if err != nil {
		t.Fatal(err)
	}
	// radius already matches -> 1 setting + 1 network + 1 wlan + 2 devices = 5 updates.
	if len(p.ClassicUpdates) != 5 {
		t.Fatalf("got %d updates, want 5: %+v", len(p.ClassicUpdates), p.ClassicUpdates)
	}

	// Verify EdgeSW unsets speed & full_duplex on port 1 while keeping port 2.
	var edge ClassicUpdate
	for _, u := range p.ClassicUpdates {
		if u.Label == `device "EdgeSW"` {
			edge = u
		}
	}
	po := edge.Body["port_overrides"].([]any)
	p1 := po[0].(obj)
	if _, hasSpeed := p1["speed"]; hasSpeed {
		t.Errorf("expected speed unset on port 1, got %v", p1)
	}
	if len(po) != 2 || po[1].(obj)["name"] != "P2" {
		t.Errorf("port 2 lost or altered: %v", po)
	}
}

func TestBuildPlanMDNS(t *testing.T) {
	d := testDecl(t)
	d.MDNS = MDNSDecl{Mode: "all", Networks: []string{"Default", "Media", "IoT"}}
	s := testState(t)
	s.MDNS["mode"] = "custom"
	s.ClassicNetworks["Default"] = "c-default"
	p, err := buildPlan(d, s)
	if err != nil {
		t.Fatal(err)
	}
	if p.MDNSMode == nil || *p.MDNSMode != [2]string{"custom", "all"} {
		t.Errorf("mode = %v", p.MDNSMode)
	}
	if p.MDNSNetworks == nil || !slices.Equal(p.MDNSNetworks[1], []string{"Default", "IoT", "Media"}) {
		t.Errorf("networks = %v", p.MDNSNetworks)
	}
	d.MDNS.Networks = []string{"Nope"}
	if _, err := buildPlan(d, s); err == nil {
		t.Error("unknown mdns network: want error")
	}
}

func TestBuildPlanErrors(t *testing.T) {
	d := testDecl(t)
	d.Policies[0]["source"].(obj)["zone"] = "Mars"
	if _, err := buildPlan(d, testState(t)); err == nil || !strings.Contains(err.Error(), `unknown zone "Mars"`) {
		t.Errorf("unknown zone: err = %v", err)
	}
	d = testDecl(t)
	d.Policies[1]["source"].(obj)["trafficFilter"].(obj)["ipAddressFilter"].(obj)["trafficMatchingList"] = "Nope"
	if _, err := buildPlan(d, testState(t)); err == nil || !strings.Contains(err.Error(), `unknown traffic matching list "Nope"`) {
		t.Errorf("unknown list: err = %v", err)
	}
	s := testState(t)
	s.Policies = append(s.Policies, deepCopy(s.Policies[0]).(obj))
	if _, err := buildPlan(testDecl(t), s); err == nil || !strings.Contains(err.Error(), "more than one policy") {
		t.Errorf("duplicate live policy: err = %v", err)
	}
}

func TestDesiredOrder(t *testing.T) {
	got := desiredOrder(Ordering{Before: []string{"a", "x", "b"}, After: []string{"c", "y"}}, []string{"y", "b", "a"}, map[string]bool{"c": true})
	if !slices.Equal(got.Before, []string{"y", "b", "a", "x"}) || len(got.After) != 0 {
		t.Errorf("got %+v", got)
	}
}

func TestLoadDeclarationsRejectsSecretsAndScrubBackup(t *testing.T) {
	dir := t.TempDir()
	files := map[string]string{
		"firewall-policies.json":      `[{"name":"a","source":{"zone":"Internal","x_passphrase":"p"},"destination":{"zone":"External"}}]`,
		"traffic-matching-lists.json": `[]`,
		"mdns.json":                   `{"mode":"all","networks":[]}`,
	}
	for n, c := range files {
		if err := os.WriteFile(filepath.Join(dir, n), []byte(c), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := loadDeclarations(dir); err == nil || !strings.Contains(err.Error(), "x_passphrase") {
		t.Errorf("err = %v", err)
	}

	bdir := t.TempDir()
	if err := writeBackup(bdir, "secret-test", obj{"name": "home", "x_passphrase": "hunter2"}); err != nil {
		t.Fatal(err)
	}
	raw, err := os.ReadFile(filepath.Join(bdir, "secret-test.json"))
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(raw), "hunter2") || !strings.Contains(string(raw), "REDACTED") {
		t.Errorf("backup leaked secret: %s", raw)
	}
}

func TestLoadDeclarationsRepo(t *testing.T) {
	d, err := loadDeclarations(filepath.Join("..", "controller"))
	if err != nil {
		t.Fatal(err)
	}
	if len(d.Policies) == 0 || len(d.Zones) == 0 || len(d.AbsentPolicies) == 0 || d.MDNS.Mode != "all" {
		t.Errorf("unexpected declarations: %d policies, %d zones, %d absent, mode %q", len(d.Policies), len(d.Zones), len(d.AbsentPolicies), d.MDNS.Mode)
	}
	if len(d.Settings.Settings) == 0 || len(d.Settings.Networks) == 0 || len(d.Settings.WLANs) == 0 || len(d.Settings.Devices) == 0 {
		t.Errorf("expected settings/networks/wlans/devices in settings.json")
	}
	if b := encode(d.Policies); strings.Contains(b, "zoneId") || strings.Contains(b, "networkIds") {
		t.Error("declarations must reference zones and networks by name, not ID")
	}
}
