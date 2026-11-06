package ma.ens.security.web;

import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.client.registration.ClientRegistration;
import org.springframework.security.oauth2.client.registration.ClientRegistrationRepository;
import org.springframework.security.oauth2.core.user.OAuth2User;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;

import java.util.ArrayList;
import java.util.List;

@Controller
public class HomeController {

    private final ClientRegistrationRepository clientRegistrationRepository;

    public HomeController(ClientRegistrationRepository clientRegistrationRepository) {
        this.clientRegistrationRepository = clientRegistrationRepository;
    }

    @GetMapping("/")
    public String home() {
        return "index";
    }

    @GetMapping("/login")
    public String login(Model model) {
        List<Fournisseur> fournisseurs = new ArrayList<>();
        if (clientRegistrationRepository instanceof Iterable<?> iterable) {
            for (Object element : iterable) {
                ClientRegistration registration = (ClientRegistration) element;
                fournisseurs.add(new Fournisseur(registration.getRegistrationId(),
                        registration.getClientName()));
            }
        }
        model.addAttribute("fournisseurs", fournisseurs);
        return "login";
    }

    @GetMapping("/profile")
    public String profile(Model model, @AuthenticationPrincipal OAuth2User user) {
        model.addAttribute("name", user.getAttribute("name"));
        model.addAttribute("email", user.getAttribute("email"));
        model.addAttribute("picture", user.getAttribute("picture"));
        model.addAttribute("sub", user.getAttribute("sub"));
        model.addAttribute("locale", user.getAttribute("locale"));
        model.addAttribute("emailVerified", user.getAttribute("email_verified"));
        model.addAttribute("attributs", user.getAttributes());
        model.addAttribute("autorites", user.getAuthorities());
        return "profile";
    }

    public record Fournisseur(String id, String nom) {
    }
}
