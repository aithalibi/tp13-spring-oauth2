package ma.ens.security;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.security.oauth2.client.registration.ClientRegistration;
import org.springframework.security.oauth2.client.registration.ClientRegistrationRepository;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Verifie la configuration OAuth2 (etapes 2 et 3 du TP) :
 * enregistrement du client, scopes, URL de redirection et point d'entree
 * de l'autorisation (/oauth2/authorization/{registrationId}).
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class OAuth2ConfigurationTest {

    @Autowired
    private ClientRegistrationRepository repository;

    @Autowired
    private MockMvc mockMvc;

    @Test
    @DisplayName("Le fournisseur est bien enregistre aupres du repository")
    void fournisseurEnregistre() {
        List<String> ids = new ArrayList<>();
        for (Object element : (Iterable<?>) repository) {
            ids.add(((ClientRegistration) element).getRegistrationId());
        }
        assertThat(ids).contains("test");
    }

    @Test
    @DisplayName("L'enregistrement contient le client-id, le secret et l'URI de redirection")
    void enregistrementComplet() {
        ClientRegistration registration = repository.findByRegistrationId("test");

        assertThat(registration.getClientId()).isEqualTo("test-client");
        assertThat(registration.getClientSecret()).isEqualTo("test-secret");
        assertThat(registration.getRedirectUri())
                .isEqualTo("{baseUrl}/login/oauth2/code/test");
        assertThat(registration.getAuthorizationGrantType().getValue()).isEqualTo("authorization_code");
    }

    @Test
    @DisplayName("Les scopes openid, profile et email sont demandes")
    void scopesDemandes() {
        ClientRegistration registration = repository.findByRegistrationId("test");

        assertThat(registration.getScopes())
                .containsExactlyInAnyOrder("openid", "profile", "email");
    }

    @Test
    @DisplayName("Les points d'autorisation, de token et de userinfo sont configures")
    void pointsDuFournisseurConfigures() {
        ClientRegistration registration = repository.findByRegistrationId("test");

        assertThat(registration.getProviderDetails().getAuthorizationUri())
                .isEqualTo("http://localhost:9999/oauth2/authorize");
        assertThat(registration.getProviderDetails().getTokenUri())
                .isEqualTo("http://localhost:9999/oauth2/token");
        assertThat(registration.getProviderDetails().getUserInfoEndpoint().getUri())
                .isEqualTo("http://localhost:9999/oauth2/userinfo");
    }

    @Test
    @DisplayName("/oauth2/authorization/{id} redirige vers le fournisseur")
    void pointDEntreeRedirigeVersLeFournisseur() throws Exception {
        String location = mockMvc.perform(get("/oauth2/authorization/test"))
                .andExpect(status().is3xxRedirection())
                .andReturn().getResponse().getRedirectedUrl();

        assertThat(location)
                .startsWith("http://localhost:9999/oauth2/authorize?")
                .contains("response_type=code")
                .contains("client_id=test-client")
                .contains("scope=openid%20profile%20email")
                .contains("state=")
                .contains("redirect_uri=http://localhost/login/oauth2/code/test");
    }

    @Test
    @DisplayName("/login propose le fournisseur configure")
    void pageLoginListeLeFournisseur() throws Exception {
        mockMvc.perform(get("/login"))
                .andExpect(status().isOk())
                .andExpect(content().string(org.hamcrest.Matchers.containsString("Test Provider")));
    }
}
