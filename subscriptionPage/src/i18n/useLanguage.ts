import { useContext } from 'react'
import { LanguageContext, type LanguageContextValue, type SupportedLanguage } from './LanguageProvider'
import type { TranslationKey } from './en'

export { type SupportedLanguage, type TranslationKey }

export function useLanguage(): LanguageContextValue {
  const ctx = useContext(LanguageContext)
  if (!ctx) throw new Error('useLanguage must be used within LanguageProvider')
  return ctx
}
