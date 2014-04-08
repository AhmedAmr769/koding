// Package main provides ...
package main

import (
	"errors"
	"fmt"
	"koding/db/models"
	"koding/db/mongodb/modelhelper"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/tsenart/tb"
)

var (
	rests     = make(map[string]models.Restriction)
	restsMu   sync.RWMutex
	buckets   = make(map[string]*tb.Bucket)
	bucketsMu sync.RWMutex
)

type Checker interface {
	Check() bool
}

type CheckIP struct {
	IP      string
	Pattern string
}

type CheckCountry struct {
	Country string
	Pattern string
}

type CheckRequest struct {
	Host       string
	MaxRequest int
	Interval   time.Duration
}

func firewallHandler(h http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var rest models.Restriction
		var ok bool

		restsMu.RLock()
		rest, ok = rests[r.Host]
		restsMu.RUnlock()
		if !ok {
			var err error
			rest, err = modelhelper.GetRestrictionByDomain(r.Host)
			if err != nil {
				// don't block if we don't get a rule (pre-caution))
				fmt.Println("no restriction available")
				h.ServeHTTP(w, r)
				return
			}

			restsMu.Lock()
			rests[r.Host] = rest
			restsMu.Unlock()
		}

		fmt.Printf("%d restrictions \n", len(rest.RuleList))
		for _, rule := range rest.RuleList {
			fmt.Printf("rule %+v\n", rule)
			if a := ApplyRule(rule, r); a != nil {
				a.ServeHTTP(w, r)
				return
			}
		}

		h.ServeHTTP(w, r)
	})
}

// ApplyRule checks the rule and returns an http.Handler to be executed. A nil
// handler means there is no http.Handler to be executed. For example if the
// user is allowed to pass,  a "nil" http.Handler is returned, however if the
// user is denied a `quotaExceeded` template handler is returned that neneeds
// to be exectued
func ApplyRule(rule models.Rule, r *http.Request) http.Handler {
	if !rule.Enabled {
		return nil
	}

	filter, err := modelhelper.GetFilterByField("name", rule.Name)
	if err != nil {
		return nil // if not found just continue with next rule
	}

	fmt.Printf("filter %+v\n", filter)

	// country is empty for now
	checker, err := GetChecker(filter, getIP(r.RemoteAddr), "", r.Host)
	if err != nil {
		fmt.Println("GetChecker", err)
		return nil
	}

	matched := checker.Check()
	switch rule.Action {
	case "deny":
		if matched {
			return templateHandler("quotaExceeded.html", r.Host, 509)
		}
	case "allow":
		if !matched {
			return templateHandler("quotaExceeded.html", r.Host, 509)
		}
	case "securepage":
		if !matched {
			return nil
		}

		session, _ := store.Get(r, CookieVM)
		log.Debug("getting cookie for: %s", r.Host)
		cookieValue, ok := session.Values[r.Host]
		if !ok || cookieValue != MagicCookieValue {
			return securePageHandler(session)
		}
	}

	return nil
}

func GetChecker(f models.Filter, ip, country, host string) (Checker, error) {
	fmt.Printf("ip %+v\n", ip)

	switch f.Type {
	case "ip":
		return &CheckIP{IP: ip, Pattern: f.Match}, nil
	case "country":
		return &CheckCountry{Country: country, Pattern: f.Match}, nil
	case "request.second", "request.minute", "request.hour", "request.day":
		rate, err := strconv.Atoi(f.Match)
		if err != nil {
			return nil, err
		}

		var freq time.Duration
		switch strings.TrimPrefix(f.Type, "request.") {
		case "second":
			freq = time.Second
		case "minute":
			freq = time.Minute
		case "hour":
			freq = time.Hour
		case "day":
			freq = time.Hour * 24
		default:
			return nil, errors.New("request type malformed")
		}

		return &CheckRequest{Host: host, MaxRequest: rate, Interval: freq}, nil
	}

	return nil, fmt.Errorf("no checker found for %s", f.Type)
}

func (c *CheckRequest) Check() bool {
	var b *tb.Bucket
	bucketsMu.RLock()
	b, ok := buckets[c.Host]
	bucketsMu.RUnlock()
	if !ok {
		b = tb.NewBucket(int64(c.MaxRequest), c.Interval)
		bucketsMu.Lock()
		buckets[c.Host] = b
		bucketsMu.Unlock()
	}

	available := b.Take(1) // one request

	fmt.Printf("available %+v\n", available)
	if available == 0 {
		return false
	}

	return true
}

func (c *CheckCountry) Check() bool {
	if c.Pattern == "all" {
		return true
	}

	if c.Pattern == c.Country {
		return true
	}

	return false
}

func (c *CheckIP) Check() bool {
	if c.Pattern == "all" {
		// assume allowed for all
		return true
	}

	matched, err := regexp.MatchString(c.Pattern, c.IP)
	if err != nil {
		// do not block if the regex fails
		return true
	}

	if matched {
		return false
	}

	return true // not matched, give access
}
