package main

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

// errManual means everything applicable was applied but a change the API
// cannot make (the mDNS network list) is still pending.
var errManual = errors.New("manual step pending (see \"! manual\" above)")

// load reads the live state plus the orderings of every zone pair the
// declarations touch.
func load(ctx context.Context, c *Client, d *Declarations) (*State, *Plan, error) {
	s, err := c.fetchState(ctx)
	if err != nil {
		return nil, nil, err
	}
	for _, p := range d.Policies {
		src, sok := s.Names.Zones[sideZone(p, "source")]
		dst, dok := s.Names.Zones[sideZone(p, "destination")]
		k := [2]string{src, dst}
		if _, done := s.Orders[k]; !sok || !dok || done {
			continue // unknown zones are reported by buildPlan
		}
		o, err := c.ordering(ctx, src, dst)
		if err != nil {
			return nil, nil, err
		}
		s.Orders[k] = o
	}
	p, err := buildPlan(d, s)
	return s, p, err
}

func apply(ctx context.Context, c *Client, d *Declarations, in io.Reader, out io.Writer, yes bool) error {
	_, p, err := load(ctx, c, d)
	if err != nil {
		return err
	}
	p.Print(out)
	if p.Empty() {
		return nil
	}
	onlyManual := len(p.Lists) == 0 && len(p.Policies) == 0 && len(p.Orders) == 0 && p.MDNSMode == nil
	if onlyManual {
		return errManual
	}
	if !yes {
		fmt.Fprint(out, "\nApply these changes to the controller? Type \"yes\": ")
		line, err := bufio.NewReader(in).ReadString('\n')
		if err != nil && !errors.Is(err, io.EOF) {
			return err
		}
		if strings.TrimSpace(line) != "yes" {
			return errors.New("aborted")
		}
	}
	backup, err := backupDir()
	if err != nil {
		return err
	}
	fmt.Fprintf(out, "backup: %s\n", backup)

	// Each step re-reads the controller so it sees the real IDs of objects
	// created by the previous step.
	steps := []func(*Plan) error{
		func(p *Plan) error { return applyChanges(ctx, c, backup, "/traffic-matching-lists", p.Lists, out) },
		func(p *Plan) error { return applyChanges(ctx, c, backup, "/firewall/policies", p.Policies, out) },
		func(p *Plan) error { return applyOrders(ctx, c, backup, p.Orders, out) },
		func(p *Plan) error { return applyMDNSMode(ctx, c, backup, p, out) },
	}
	for i, step := range steps {
		if i > 0 {
			if _, p, err = load(ctx, c, d); err != nil {
				return err
			}
		}
		if err := step(p); err != nil {
			return err
		}
	}

	_, p, err = load(ctx, c, d)
	if err != nil {
		return err
	}
	fmt.Fprintln(out, "\nAfter apply:")
	p.Print(out)
	switch {
	case p.Empty():
		return nil
	case len(p.Lists) == 0 && len(p.Policies) == 0 && len(p.Orders) == 0 && p.MDNSMode == nil:
		return errManual
	default:
		return errors.New("controller still differs after apply")
	}
}

func applyChanges(ctx context.Context, c *Client, backup, path string, changes []Change, out io.Writer) error {
	for _, ch := range changes {
		if ch.ID == "" {
			fmt.Fprintf(out, "creating %s\n", ch.Label)
			if err := c.do(ctx, http.MethodPost, c.integ+path, ch.Body, nil); err != nil {
				return fmt.Errorf("create %s: %w", ch.Label, err)
			}
			continue
		}
		if err := writeBackup(backup, ch.Label, ch.Before); err != nil {
			return err
		}
		fmt.Fprintf(out, "updating %s\n", ch.Label)
		if err := c.do(ctx, http.MethodPut, c.integ+path+"/"+ch.ID, ch.Body, nil); err != nil {
			return fmt.Errorf("update %s: %w", ch.Label, err)
		}
	}
	return nil
}

func applyOrders(ctx context.Context, c *Client, backup string, orders []OrderChange, out io.Writer) error {
	for _, o := range orders {
		for _, id := range o.Desired.Before {
			if key, ok := strings.CutPrefix(id, newPrefix); ok {
				return fmt.Errorf("%s: policy %s was not created", o.Label, key)
			}
		}
		if err := writeBackup(backup, o.Label, obj{"orderedFirewallPolicyIds": o.Current}); err != nil {
			return err
		}
		fmt.Fprintf(out, "reordering %s\n", o.Label)
		if err := c.setOrdering(ctx, o.Src, o.Dst, o.Desired); err != nil {
			return fmt.Errorf("%s: %w", o.Label, err)
		}
	}
	return nil
}

func applyMDNSMode(ctx context.Context, c *Client, backup string, p *Plan, out io.Writer) error {
	if p.MDNSMode == nil {
		return nil
	}
	s, err := c.fetchState(ctx)
	if err != nil {
		return err
	}
	if err := writeBackup(backup, "mdns", s.MDNS); err != nil {
		return err
	}
	body := deepCopy(s.MDNS).(obj)
	body["mode"] = p.MDNSMode[1]
	if p.MDNSMode[1] == "all" {
		// mode=all with a service list left over from "custom" is rejected
		// with MdnsSettingInvalidServicesListException.
		body["predefined_services"] = []any{}
		body["custom_services"] = []any{}
	}
	id, _ := s.MDNS["_id"].(string)
	fmt.Fprintf(out, "updating mdns mode -> %q\n", p.MDNSMode[1])
	_, err = c.classicDo(ctx, http.MethodPut, "/rest/setting/mdns/"+id, body)
	return err
}

func backupDir() (string, error) {
	base := os.Getenv("XDG_STATE_HOME")
	if base == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		base = filepath.Join(home, ".local", "state")
	}
	dir := filepath.Join(base, "unifictl", "backup", time.Now().UTC().Format("20060102T150405Z"))
	return dir, os.MkdirAll(dir, 0o700)
}

var unsafeChars = regexp.MustCompile(`[^A-Za-z0-9._-]+`)

func writeBackup(dir, label string, v any) error {
	b, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return err
	}
	name := strings.Trim(unsafeChars.ReplaceAllString(label, "_"), "_") + ".json"
	return os.WriteFile(filepath.Join(dir, name), b, 0o600)
}
