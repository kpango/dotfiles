// unifictl applies the hand-written, secret-free UniFi controller declarations
// in unifi/controller/ (firewall policies, traffic matching lists, mDNS mode)
// to the UDM Pro. Design decisions: unifi/CONTEXT.md Q25–Q31.
//
// Usage:
//
//	unifictl [-dir unifi/controller] plan
//	unifictl [-dir unifi/controller] [-yes] apply
//
// Environment: UNIFI_API_KEY (required), UNIFI_HOST (default 10.0.0.1),
// UNIFI_SITE (default "default").
//
// It never writes API responses into the repository; apply saves the objects
// it changes under $XDG_STATE_HOME/unifictl/backup/<timestamp>/.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/signal"
)

func main() {
	os.Exit(run())
}

func run() int {
	dir := flag.String("dir", "unifi/controller", "directory holding the declarations")
	yes := flag.Bool("yes", false, "apply without the interactive confirmation")
	flag.Parse()
	if flag.NArg() != 1 || (flag.Arg(0) != "plan" && flag.Arg(0) != "apply") {
		fmt.Fprintln(os.Stderr, "usage: unifictl [-dir DIR] [-yes] plan|apply")
		return 2
	}
	key := os.Getenv("UNIFI_API_KEY")
	if key == "" {
		fmt.Fprintln(os.Stderr, "unifictl: UNIFI_API_KEY is not set")
		return 2
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()

	d, err := loadDeclarations(*dir)
	if err != nil {
		fmt.Fprintln(os.Stderr, "unifictl:", err)
		return 1
	}
	c, err := newClient(ctx, envOr("UNIFI_HOST", "10.0.0.1"), key, envOr("UNIFI_SITE", "default"))
	if err != nil {
		fmt.Fprintln(os.Stderr, "unifictl:", err)
		return 1
	}
	if flag.Arg(0) == "plan" {
		_, p, err := load(ctx, c, d)
		if err != nil {
			fmt.Fprintln(os.Stderr, "unifictl:", err)
			return 1
		}
		p.Print(os.Stdout)
		return 0
	}
	if err := apply(ctx, c, d, os.Stdin, os.Stdout, *yes); err != nil {
		fmt.Fprintln(os.Stderr, "unifictl:", err)
		if errors.Is(err, errManual) {
			return 3
		}
		return 1
	}
	return 0
}

func envOr(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}
