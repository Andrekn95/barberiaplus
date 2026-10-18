import { useEffect } from 'react'
import { supabase } from './services/supabase'

export default function App() {
  useEffect(() => {
    supabase
      .from('servicios')
      .select('*')
      .then(({ data, error }) => console.log('data:', data, 'error:', error))
  }, [])

  return <h1>Barbería</h1>
}