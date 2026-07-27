import { createContext, useState, useCallback, type ReactNode } from 'react'
import en from './en'
import ru from './ru'
import type { Translation, TranslationKey } from './en'

export type SupportedLanguage = 'en' | 'ru'

export interface LanguageContextValue {
  language: SupportedLanguage
  setLanguage: (lang: SupportedLanguage) => void
  t: (key: TranslationKey, params?: Record<string, string | number>) => string
}

const translations: Record<SupportedLanguage, Translation> = { en, ru }

function detectLanguage(): SupportedLanguage {
  try {
    const stored = localStorage.getItem('olcwave-lang')
    if (stored === 'en' || stored === 'ru') return stored
  } catch {}
  try {
    const lang = navigator.language
    if (lang.startsWith('ru')) return 'ru'
  } catch {}
  return 'en'
}

export const LanguageContext = createContext<LanguageContextValue>(null!)

export function LanguageProvider({ children }: { children: ReactNode }) {
  const [language, setLanguageState] = useState<SupportedLanguage>(detectLanguage)

  const setLanguage = useCallback((lang: SupportedLanguage) => {
    setLanguageState(lang)
    try {
      localStorage.setItem('olcwave-lang', lang)
    } catch {}
  }, [])

  const t = useCallback(
    (key: TranslationKey, params?: Record<string, string | number>) => {
      let text = translations[language][key]
      if (text === undefined) text = en[key]
      if (params) {
        for (const [k, v] of Object.entries(params)) {
          text = text.replace(new RegExp(`\\{${k}\\}`, 'g'), String(v))
        }
      }
      return text
    },
    [language],
  )

  return (
    <LanguageContext.Provider value={{ language, setLanguage, t }}>
      {children}
    </LanguageContext.Provider>
  )
}
