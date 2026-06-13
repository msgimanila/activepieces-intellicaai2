import { createFileRoute } from '@tanstack/react-router'
import CustomPageModule from '@/modules/custom-pages/custompage'

export const Route = createFileRoute('/custompage')({
  component: CustomPageModule,
})
