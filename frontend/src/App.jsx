import { BrowserRouter, Routes, Route } from 'react-router-dom'
import Home from '@/pages/Home'
import LicensePlate from '@/pages/LicensePlate'

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<Home />} />
        <Route path="/license-plate" element={<LicensePlate />} />
      </Routes>
    </BrowserRouter>
  )
}
