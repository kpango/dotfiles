package main

import (
	"bufio"
	"bytes"
	"context"
	"fmt"
	"io"
)

type Server struct {
	prompter Prompter
	in       io.Reader
	out      io.Writer
}

func NewServer(p Prompter, in io.Reader, out io.Writer) *Server {
	return &Server{
		prompter: p,
		in:       in,
		out:      out,
	}
}

func (s *Server) Serve(ctx context.Context) {
	w := bufio.NewWriter(s.out)
	send := func(line string) {
		fmt.Fprintln(w, line)
		w.Flush()
	}

	send("OK Pleased to meet you")

	var desc, prompt, errMsg, title string
	prompt = "Passphrase"
	title = "GPG"

	scanner := bufio.NewScanner(s.in)
	space := []byte(" ")
	carriage := []byte("\r")

	for scanner.Scan() {
		line := bytes.TrimRight(scanner.Bytes(), string(carriage))
		cmd, arg, _ := bytes.Cut(line, space)

		if bytes.EqualFold(cmd, []byte("SETDESC")) {
			desc = assuanDecode(arg)
			send("OK")
		} else if bytes.EqualFold(cmd, []byte("SETPROMPT")) {
			prompt = assuanDecode(arg)
			send("OK")
		} else if bytes.EqualFold(cmd, []byte("SETERROR")) {
			errMsg = assuanDecode(arg)
			send("OK")
		} else if bytes.EqualFold(cmd, []byte("SETTITLE")) {
			title = assuanDecode(arg)
			send("OK")
		} else if bytes.EqualFold(cmd, []byte("RESET")) {
			desc = ""
			prompt = "Passphrase"
			errMsg = ""
			title = "GPG"
			send("OK")
		} else if bytes.EqualFold(cmd, []byte("GETPIN")) {
			w.Flush()
			if s.prompter.GetPin(ctx, title, prompt, errMsg) {
				send("OK")
			} else {
				send("ERR 83886179 Operation cancelled")
			}
		} else if bytes.EqualFold(cmd, []byte("CONFIRM")) || bytes.EqualFold(cmd, []byte("MESSAGE")) {
			if s.prompter.Confirm(ctx, desc) {
				send("OK")
			} else {
				send("ERR 277 Operation cancelled")
			}
		} else if bytes.EqualFold(cmd, []byte("BYE")) {
			send("OK closing connection")
			return
		} else {
			send("OK")
		}
	}
}
