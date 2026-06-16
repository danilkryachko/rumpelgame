package main

import "testing"

func TestConfiguredServerAddressDefaultsToLoopback(t *testing.T) {
	t.Setenv("RUMPELMC_SERVER_ADDRESS", "")

	got, err := configuredServerAddress()
	if err != nil {
		t.Fatalf("configuredServerAddress() error = %v", err)
	}
	want := "127.0.0.1:25565"
	if got != want {
		t.Fatalf("configuredServerAddress() = %q, want %q", got, want)
	}
}

func TestConfiguredServerAddressAllowsLoopbackOverrides(t *testing.T) {
	for _, address := range []string{
		"127.0.0.1:25566",
		"localhost:25566",
		"[::1]:25566",
	} {
		t.Run(address, func(t *testing.T) {
			t.Setenv("RUMPELMC_SERVER_ADDRESS", address)

			got, err := configuredServerAddress()
			if err != nil {
				t.Fatalf("configuredServerAddress() error = %v", err)
			}
			if got != address {
				t.Fatalf("configuredServerAddress() = %q, want %q", got, address)
			}
		})
	}
}

func TestConfiguredServerAddressRejectsNonLoopbackOverrides(t *testing.T) {
	for _, address := range []string{
		"0.0.0.0:25565",
		":25565",
		"[::]:25565",
		"192.168.1.10:25565",
		"example.com:25565",
		"not-a-host-port",
	} {
		t.Run(address, func(t *testing.T) {
			t.Setenv("RUMPELMC_SERVER_ADDRESS", address)

			if got, err := configuredServerAddress(); err == nil {
				t.Fatalf("configuredServerAddress() = %q, want error", got)
			}
		})
	}
}
