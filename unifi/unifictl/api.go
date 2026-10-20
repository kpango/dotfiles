package main

import (
	"bytes"
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"
)

// Client talks to the Integration API (firewall, lists, zones, networks) and
// the classic API (mDNS setting, networkconf) of one UniFi console.
type Client struct {
	http    *http.Client
	key     string
	integ   string // https://host/proxy/network/integration/v1/sites/<siteId>
	classic string // https://host/proxy/network/api/s/<site>
}

const pageLimit = 200

func newClient(ctx context.Context, host, key, site string) (*Client, error) {
	c := &Client{
		http: &http.Client{
			Timeout: 30 * time.Second,
			// The console serves a self-signed certificate on the LAN; the API
			// key, not the certificate, authenticates this tool.
			Transport: &http.Transport{TLSClientConfig: &tls.Config{InsecureSkipVerify: true}}, //nolint:gosec
		},
		key:     key,
		classic: "https://" + host + "/proxy/network/api/s/" + url.PathEscape(site),
	}
	var sites []obj
	if err := c.list(ctx, "https://"+host+"/proxy/network/integration/v1/sites", &sites); err != nil {
		return nil, err
	}
	for _, s := range sites {
		if s["internalReference"] == site {
			id, _ := s["id"].(string)
			c.integ = "https://" + host + "/proxy/network/integration/v1/sites/" + id
			return c, nil
		}
	}
	return nil, fmt.Errorf("site %q not found", site)
}

func (c *Client) do(ctx context.Context, method, u string, body, out any) error {
	var r io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			return err
		}
		r = bytes.NewReader(b)
	}
	req, err := http.NewRequestWithContext(ctx, method, u, r)
	if err != nil {
		return err
	}
	req.Header.Set("X-API-KEY", c.key)
	req.Header.Set("Accept", "application/json")
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	b, err := io.ReadAll(io.LimitReader(resp.Body, 16<<20))
	if err != nil {
		return err
	}
	if resp.StatusCode/100 != 2 {
		return fmt.Errorf("%s %s: HTTP %d: %.300s", method, u, resp.StatusCode, b)
	}
	if out == nil || len(b) == 0 {
		return nil
	}
	return json.Unmarshal(b, out)
}

// list reads a paged Integration API collection, refusing to silently truncate.
func (c *Client) list(ctx context.Context, u string, out *[]obj) error {
	var page struct {
		Data       []obj `json:"data"`
		Count      int   `json:"count"`
		TotalCount int   `json:"totalCount"`
	}
	if err := c.do(ctx, http.MethodGet, fmt.Sprintf("%s?limit=%d", u, pageLimit), nil, &page); err != nil {
		return err
	}
	if page.TotalCount > len(page.Data) {
		return fmt.Errorf("%s: %d objects exceed one page of %d", u, page.TotalCount, pageLimit)
	}
	*out = page.Data
	return nil
}

// classic calls the classic API, whose envelope reports errors in meta.rc
// even on HTTP 200.
func (c *Client) classicDo(ctx context.Context, method, path string, body any) ([]obj, error) {
	var env struct {
		Meta struct {
			RC  string `json:"rc"`
			Msg string `json:"msg"`
		} `json:"meta"`
		Data []obj `json:"data"`
	}
	if err := c.do(ctx, method, c.classic+path, body, &env); err != nil {
		return nil, err
	}
	if env.Meta.RC != "ok" {
		return nil, fmt.Errorf("%s %s: rc=%s %s", method, path, env.Meta.RC, env.Meta.Msg)
	}
	return env.Data, nil
}

// State is the live controller state this tool compares against.
type State struct {
	Names           Names
	Policies        []obj // USER_DEFINED only
	Lists           []obj
	Orders          map[[2]string]Ordering // key: {srcZoneID, dstZoneID}
	MDNS            obj
	ClassicNetworks map[string]string // name -> classic networkconf _id
}

type Ordering struct {
	Before []string `json:"beforeSystemDefined"`
	After  []string `json:"afterSystemDefined"`
}

func (c *Client) fetchState(ctx context.Context) (*State, error) {
	s := &State{
		Names:           Names{Zones: map[string]string{}, Networks: map[string]string{}, Lists: map[string]string{}},
		Orders:          map[[2]string]Ordering{},
		ClassicNetworks: map[string]string{},
	}
	var zones, nets, pols []obj
	for _, x := range []struct {
		path string
		out  *[]obj
	}{{"/firewall/zones", &zones}, {"/networks", &nets}, {"/traffic-matching-lists", &s.Lists}, {"/firewall/policies", &pols}} {
		if err := c.list(ctx, c.integ+x.path, x.out); err != nil {
			return nil, err
		}
	}
	if err := indexNames(zones, s.Names.Zones, "zone"); err != nil {
		return nil, err
	}
	if err := indexNames(nets, s.Names.Networks, "network"); err != nil {
		return nil, err
	}
	if err := indexNames(s.Lists, s.Names.Lists, "traffic matching list"); err != nil {
		return nil, err
	}
	for _, p := range pols {
		if m, _ := p["metadata"].(obj); m["origin"] == "USER_DEFINED" {
			s.Policies = append(s.Policies, p)
		}
	}
	settings, err := c.classicDo(ctx, http.MethodGet, "/rest/setting", nil)
	if err != nil {
		return nil, err
	}
	for _, st := range settings {
		if st["key"] == "mdns" {
			s.MDNS = st
		}
	}
	if s.MDNS == nil {
		return nil, fmt.Errorf("classic setting key=mdns not found")
	}
	ncs, err := c.classicDo(ctx, http.MethodGet, "/rest/networkconf", nil)
	if err != nil {
		return nil, err
	}
	for _, n := range ncs {
		name, _ := n["name"].(string)
		id, _ := n["_id"].(string)
		s.ClassicNetworks[name] = id
	}
	return s, nil
}

func indexNames(objs []obj, into map[string]string, kind string) error {
	for _, o := range objs {
		name, _ := o["name"].(string)
		id, _ := o["id"].(string)
		if _, dup := into[name]; dup {
			return fmt.Errorf("%s name %q is not unique on the controller", kind, name)
		}
		into[name] = id
	}
	return nil
}

func (c *Client) ordering(ctx context.Context, src, dst string) (Ordering, error) {
	var r struct {
		O Ordering `json:"orderedFirewallPolicyIds"`
	}
	err := c.do(ctx, http.MethodGet, c.orderingURL(src, dst), nil, &r)
	return r.O, err
}

func (c *Client) setOrdering(ctx context.Context, src, dst string, o Ordering) error {
	return c.do(ctx, http.MethodPut, c.orderingURL(src, dst), obj{"orderedFirewallPolicyIds": o}, nil)
}

func (c *Client) orderingURL(src, dst string) string {
	q := url.Values{"sourceFirewallZoneId": {src}, "destinationFirewallZoneId": {dst}}
	return c.integ + "/firewall/policies/ordering?" + q.Encode()
}
