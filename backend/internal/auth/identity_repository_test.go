package auth

import (
	"context"
	"sync"
	"testing"
)

func TestFindOrCreateIdentityCreatesUserOnce(t *testing.T) {
	pool, _ := authTestDatabase(t)
	repository := NewIdentityRepository(pool)
	identity := Identity{Provider: ProviderGoogle, Subject: "google-subject", Email: "person@example.com", Name: "Person"}

	first, firstCreated, err := repository.FindOrCreate(context.Background(), identity)
	if err != nil {
		t.Fatalf("first find or create: %v", err)
	}
	second, secondCreated, err := repository.FindOrCreate(context.Background(), identity)
	if err != nil {
		t.Fatalf("second find or create: %v", err)
	}
	if !firstCreated || secondCreated {
		t.Fatalf("unexpected created flags: first=%t second=%t", firstCreated, secondCreated)
	}
	if first.ID != second.ID {
		t.Fatalf("expected stable user ID, got %s and %s", first.ID, second.ID)
	}

	var identityCount int
	if err := pool.QueryRow(context.Background(), "select count(*) from user_identities where provider = $1 and provider_subject = $2", identity.Provider, identity.Subject).Scan(&identityCount); err != nil {
		t.Fatalf("count identities: %v", err)
	}
	if identityCount != 1 {
		t.Fatalf("expected one identity, got %d", identityCount)
	}
}

func TestFindOrCreateDoesNotMergeDifferentProviders(t *testing.T) {
	pool, _ := authTestDatabase(t)
	repository := NewIdentityRepository(pool)

	google, _, err := repository.FindOrCreate(context.Background(), Identity{Provider: ProviderGoogle, Subject: "same-subject", Email: "person@example.com"})
	if err != nil {
		t.Fatalf("create Google identity: %v", err)
	}
	apple, _, err := repository.FindOrCreate(context.Background(), Identity{Provider: ProviderApple, Subject: "same-subject", Email: "person@example.com"})
	if err != nil {
		t.Fatalf("create Apple identity: %v", err)
	}
	if google.ID == apple.ID {
		t.Fatal("different providers were merged")
	}
}

func TestFindOrCreateHandlesConcurrentFirstLogin(t *testing.T) {
	pool, _ := authTestDatabase(t)
	repository := NewIdentityRepository(pool)
	identity := Identity{Provider: ProviderGoogle, Subject: "concurrent-subject"}

	const attempts = 8
	ids := make(chan UserID, attempts)
	errorsChannel := make(chan error, attempts)
	var waitGroup sync.WaitGroup
	for range attempts {
		waitGroup.Add(1)
		go func() {
			defer waitGroup.Done()
			user, _, err := repository.FindOrCreate(context.Background(), identity)
			if err != nil {
				errorsChannel <- err
				return
			}
			ids <- user.ID
		}()
	}
	waitGroup.Wait()
	close(ids)
	close(errorsChannel)
	for err := range errorsChannel {
		t.Errorf("concurrent find or create: %v", err)
	}

	var expected UserID
	for id := range ids {
		if expected == "" {
			expected = id
		}
		if id != expected {
			t.Errorf("received different user IDs: %s and %s", expected, id)
		}
	}
}
