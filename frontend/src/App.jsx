import { useEffect } from 'react'
import { BrowserRouter, Routes, Route } from 'react-router-dom'
import Home from '@/pages/Home'
import LicensePlate from '@/pages/LicensePlate'
import { useStore } from '@/store/useStore'

export default function App() {
  const logout = useStore((state) => state.logout)

  useEffect(() => {
    const handleAuthLogout = () => logout()
    window.addEventListener('auth:logout', handleAuthLogout)
    return () => window.removeEventListener('auth:logout', handleAuthLogout)
  }, [logout])

  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<Home />} />
        <Route path="/license-plate" element={<LicensePlate />} />
      </Routes>
    </BrowserRouter>
  )
}
