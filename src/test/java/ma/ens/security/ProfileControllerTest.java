package ma.ens.security;

import ma.ens.security.web.HomeController;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.oauth2Login;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.model;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.view;

/**
 * Verifie l'affichage du profil a partir d'un utilisateur OAuth2 simule
 * (etape 4 du TP) : les attributs du jeton d'identite doivent alimenter la vue.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class ProfileControllerTest {

    @Autowired
    private MockMvc mockMvc;

    private static final String NOM = "Yasmine Ait Halibi";
    private static final String EMAIL = "yasmine.ait@ens.ma";
    private static final String PHOTO = "https://exemple.ma/photo.png";
    private static final String SUB = "mock|yasmine";

    @Test
    @DisplayName("Un utilisateur authentifie via OAuth2 accede a /profile")
    void profilAccessibleAvecOAuth2User() throws Exception {
        mockMvc.perform(get("/profile").with(oauth2Login()
                        .attributes(attrs -> {
                            attrs.put("sub", SUB);
                            attrs.put("name", NOM);
                            attrs.put("email", EMAIL);
                            attrs.put("picture", PHOTO);
                            attrs.put("email_verified", true);
                            attrs.put("locale", "fr");
                        })))
                .andExpect(status().isOk())
                .andExpect(view().name("profile"))
                .andExpect(model().attribute("name", NOM))
                .andExpect(model().attribute("email", EMAIL))
                .andExpect(model().attribute("picture", PHOTO))
                .andExpect(model().attribute("sub", SUB));
    }

    @Test
    @DisplayName("La vue profil affiche le nom, l'email et la photo")
    void vueProfilAfficheLesAttributs() throws Exception {
        mockMvc.perform(get("/profile").with(oauth2Login()
                        .attributes(attrs -> {
                            attrs.put("sub", SUB);
                            attrs.put("name", NOM);
                            attrs.put("email", EMAIL);
                            attrs.put("picture", PHOTO);
                        })))
                .andExpect(status().isOk())
                .andExpect(content().string(containsString(NOM)))
                .andExpect(content().string(containsString(EMAIL)))
                .andExpect(content().string(containsString(PHOTO)))
                .andExpect(content().string(containsString("Connecte via OAuth2 / OIDC")));
    }

    @Test
    @DisplayName("Un attribut absent n'empeche pas l'affichage du profil")
    void attributAbsentAfficheUneValeurParDefaut() throws Exception {
        mockMvc.perform(get("/profile").with(oauth2Login()
                        .attributes(attrs -> {
                            attrs.put("sub", SUB);
                            attrs.put("name", NOM);
                        })))
                .andExpect(status().isOk())
                .andExpect(content().string(containsString(NOM)))
                .andExpect(content().string(containsString("(non fourni)")));
    }

    @Test
    @DisplayName("Les attributs bruts du OAuth2User sont exposes dans le modele")
    void attributsBrutsExposes() throws Exception {
        mockMvc.perform(get("/profile").with(oauth2Login()
                        .attributes(attrs -> {
                            attrs.put("sub", SUB);
                            attrs.put("name", NOM);
                            attrs.put("email", EMAIL);
                        })))
                .andExpect(status().isOk())
                .andExpect(model().attributeExists("attributs"))
                .andExpect(model().attributeExists("autorites"));
    }

    @Test
    @DisplayName("Le nom de l'utilisateur est bien le 'sub' du jeton")
    void nomUtilisateurCorrespondAuSub() throws Exception {
        mockMvc.perform(get("/profile").with(oauth2Login()
                        .attributes(attrs -> {
                            attrs.put("sub", SUB);
                            attrs.put("name", NOM);
                        })))
                .andExpect(status().isOk())
                .andExpect(content().string(containsString(SUB)));
    }
}
