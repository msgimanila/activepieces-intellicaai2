import { t } from 'i18next';

const FullLogo = () => {
  return (
    <div className="h-[60px]">
      <img 
        className="h-full" 
        src="https://intellicaai.space/wp-content/uploads/2025/07/intellicaai.png" 
        alt={t('logo')} 
        />
    </div>
  );
};

FullLogo.displayName = 'FullLogo';

export { FullLogo };
