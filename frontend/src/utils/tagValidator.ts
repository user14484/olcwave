import { profilesApi } from '../api/profiles'
import type { TagValidationResult } from '../types'

const TAG_REGEX = /^[a-zA-Z0-9_]+$/

export function validateTagSync(tag: string): { valid: false; message: string } | null {
  if (!tag.trim()) {
    return { valid: false, message: 'Tag cannot be empty' }
  }
  if (!TAG_REGEX.test(tag)) {
    return { valid: false, message: 'Tag may contain only letters, numbers, and underscores.' }
  }
  return null
}

export async function checkTag(tag: string, excludeTag?: string): Promise<TagValidationResult> {
  const syncResult = validateTagSync(tag)
  if (syncResult) {
    return syncResult
  }

  try {
    const profiles = await profilesApi.getAll().then((r) => r.data)
    const exists = profiles.some((p) => p.tag === tag && p.tag !== excludeTag)
    if (exists) {
      return { valid: false, message: 'Tag already exists' }
    }
    return { valid: true }
  } catch {
    return { valid: false, message: 'Could not verify tag uniqueness' }
  }
}