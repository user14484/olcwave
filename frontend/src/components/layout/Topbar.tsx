import { useState, useRef, useEffect } from 'react'
import { useLocation } from 'react-router-dom'
import { useLanguage, type TranslationKey, type SupportedLanguage } from '../../i18n/useLanguage'
import { useAuthStore } from '../../store/auth'

const pageTitles: Record<string, { titleKey: TranslationKey; subtitleKey: TranslationKey }> = {
  '/dashboard': { titleKey: 'pageDashboard', subtitleKey: 'pageDashboardSubtitle' },
  '/users': { titleKey: 'pageUsers', subtitleKey: 'pageUsersSubtitle' },
  '/profiles': { titleKey: 'pageProfiles', subtitleKey: 'pageProfilesSubtitle' },
  '/routing': { titleKey: 'pageRouting', subtitleKey: 'pageRoutingSubtitle' },
  '/containers': { titleKey: 'pageContainers', subtitleKey: 'pageContainersSubtitle' },
  '/subscriptions': { titleKey: 'pageSubscriptions', subtitleKey: 'pageSubscriptionsSubtitle' },
  '/settings': { titleKey: 'pageSettings', subtitleKey: 'pageSettingsSubtitle' },
}

const languages: { value: SupportedLanguage; labelKey: TranslationKey }[] = [
  { value: 'en', labelKey: 'english' },
  { value: 'ru', labelKey: 'russian' },
]

export default function Topbar() {
  const { t, language, setLanguage } = useLanguage()
  const location = useLocation()
  const page = pageTitles[location.pathname] || pageTitles['/dashboard']
  const username = useAuthStore((s) => s.username)
  const [langOpen, setLangOpen] = useState(false)
  const ref = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!langOpen) return
    const onClick = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setLangOpen(false)
    }
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && setLangOpen(false)
    document.addEventListener('mousedown', onClick)
    window.addEventListener('keydown', onKey)
    return () => {
      document.removeEventListener('mousedown', onClick)
      window.removeEventListener('keydown', onKey)
    }
  }, [langOpen])

  return (
    <header className="sticky top-0 z-20 h-14 bg-bg-secondary/80 backdrop-blur-md border-b border-border
      flex items-center justify-between px-6 shrink-0">
      <div className="min-w-0">
        <h1 className="text-base font-semibold text-text-primary leading-tight truncate">{t(page.titleKey)}</h1>
        <p className="text-xs text-text-muted truncate">{t(page.subtitleKey)}</p>
      </div>
      <div className="flex items-center gap-3 shrink-0">
        <div ref={ref} className="relative">
          <button
            type="button"
            onClick={() => setLangOpen((v) => !v)}
            className="inline-flex items-center gap-1 h-7 px-2 rounded-md text-xs font-medium text-text-muted
              hover:text-text-primary hover:bg-bg-hover transition-colors cursor-pointer border border-border"
          >
            {t(language === 'en' ? 'english' : 'russian')}
            <svg className={`w-3 h-3 transition-transform ${langOpen ? 'rotate-180' : ''}`} fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
            </svg>
          </button>
          {langOpen && (
            <div className="absolute right-0 z-30 mt-1.5 w-32 p-1 bg-bg-elevated border border-border-light rounded-lg
              shadow-elevated animate-scale-in origin-top-right">
              {languages.map((lang) => (
                <button
                  key={lang.value}
                  onClick={() => { setLanguage(lang.value); setLangOpen(false) }}
                  className={`flex w-full items-center px-2.5 h-8 rounded-md text-xs font-medium transition-colors cursor-pointer
                    ${language === lang.value
                      ? 'bg-accent/10 text-accent'
                      : 'text-text-secondary hover:text-text-primary hover:bg-bg-hover'}`}
                >
                  {t(lang.labelKey)}
                </button>
              ))}
            </div>
          )}
        </div>
        <div className="flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-accent/10 border border-accent/20">
          <span className="text-sm font-semibold text-accent">v1.0.4</span>
        </div>
        <div className="flex items-center justify-center w-8 h-8 rounded-full bg-accent/15 text-accent text-xs font-semibold">
          {username.charAt(0).toUpperCase() || 'A'}
        </div>
      </div>
    </header>
  )
}
