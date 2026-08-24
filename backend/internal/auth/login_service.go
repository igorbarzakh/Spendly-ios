package auth

import "context"

var ErrUnsupportedProvider = ErrInvalidIdentityToken

type AuthService struct {
	verifiers  map[Provider]IdentityVerifier
	identities *IdentityRepository
	sessions   *SessionService
}

func NewAuthService(verifiers map[Provider]IdentityVerifier, identities *IdentityRepository, sessions *SessionService) *AuthService {
	return &AuthService{verifiers: verifiers, identities: identities, sessions: sessions}
}

func (service *AuthService) SignIn(ctx context.Context, provider Provider, idToken, nonce string) (User, SessionTokens, error) {
	verifier, ok := service.verifiers[provider]
	if !ok {
		return User{}, SessionTokens{}, ErrUnsupportedProvider
	}
	identity, err := verifier.Verify(ctx, idToken, nonce)
	if err != nil {
		return User{}, SessionTokens{}, err
	}
	user, _, err := service.identities.FindOrCreate(ctx, identity)
	if err != nil {
		return User{}, SessionTokens{}, err
	}
	tokens, err := service.sessions.Issue(ctx, user.ID)
	if err != nil {
		return User{}, SessionTokens{}, err
	}
	return user, tokens, nil
}
func (service *AuthService) Refresh(ctx context.Context, raw string) (SessionTokens, error) {
	return service.sessions.Refresh(ctx, raw)
}
func (service *AuthService) Logout(ctx context.Context, raw string) error {
	return service.sessions.Logout(ctx, raw)
}
func (service *AuthService) LogoutAll(ctx context.Context, userID UserID) error {
	return service.sessions.LogoutAll(ctx, userID)
}
