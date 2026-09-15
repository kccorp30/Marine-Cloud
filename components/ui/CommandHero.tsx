import Image from "next/image";
export function CommandHero({
  eyebrow,
  title,
  name,
  description,
  actions,
}: {
  eyebrow: string;
  title: string;
  name?: string;
  description: string;
  actions?: React.ReactNode;
}) {
  return (
    <section className="command-hero">
      <Image
        src="/brand/marine-hero-clean.png"
        alt=""
        fill
        priority
        sizes="(max-width: 1024px) 100vw, 80vw"
        className="command-hero-image"
      />
      <div className="command-hero-shade" />
      <div className="command-hero-content">
        <p className="eyebrow">{eyebrow}</p>
        <h1>
          {title}
          {name && (
            <>
              , <span className="text-gold-sheen">{name}</span>
            </>
          )}
        </h1>
        <p className="command-hero-description">{description}</p>
        {actions && <div className="flex flex-wrap gap-3 mt-5">{actions}</div>}
      </div>
      <span className="command-hero-signature" aria-hidden="true">
        KCC
        <br />
        MARINE CLOUD
      </span>
    </section>
  );
}
