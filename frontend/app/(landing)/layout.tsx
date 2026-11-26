import { NavbarLanding } from '@/components/landing/navbar-landing';
import { FooterLanding } from '@/components/landing/footer-landing';
import { CommandPalette } from '@/components/shared/command-palette';

/**
 * Page publique : identité volontairement sombre (« sous-bois »), quel que soit
 * le thème choisi dans l'application.
 *
 * Le site vitrine et l'espace de travail n'ont pas la même intention : une page
 * de vente se lit comme une affiche, un dashboard se lit comme un document.
 * On force donc `.dark` ici pour que les jetons sémantiques (`text-foreground`,
 * `bg-background`, `border-border`) prennent leurs valeurs sombres.
 *
 * Ne jamais remettre de couleur littérale dans ce layout : les sections enfants
 * n'utilisent que des classes sémantiques, une valeur en dur les désaccorde.
 */
export default function LandingLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="dark relative min-h-screen overflow-x-hidden bg-background text-foreground">
      <div className="relative z-10">
        <NavbarLanding />
        <main id="main-content" className="pt-[68px]">
          {children}
        </main>
        <FooterLanding />
      </div>
      <CommandPalette />
    </div>
  );
}
